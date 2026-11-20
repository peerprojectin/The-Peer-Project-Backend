import argparse
import json
import os
import re
from collections import Counter
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from supabase import create_client

EMBED_MODEL = "nvidia/llama-nemotron-embed-1b-v2"
CHAT_MODEL = "google/gemma-3-4b-it"
LIVE = ["pending", "active"]
PROMPT = (Path(__file__).parent / "prompt.txt").read_text(encoding="utf-8")


def connect():
    load_dotenv(Path(__file__).parent / ".env")
    return create_client(os.environ["SUPABASE_URL"], os.environ["SUPABASE_KEY"])


def area_labels(db):
    rows = db.table("help_area_options").select("track, area, label").execute().data
    return {(row["track"], row["area"]): row["label"] for row in rows}


def load(db, table, cohort_id, columns):
    return (
        db.table(table)
        .select(columns)
        .eq("cohort_id", cohort_id)
        .eq("status", "accepted")
        .eq("is_verified", True)
        .execute()
        .data
    )


def help_areas(rows, labels):
    parts = []
    for row in rows:
        label = labels.get((row["track"], row["area"]), row["area"])
        detail = f" ({row['area_other']})" if row.get("area_other") else ""
        parts.append(f"{row['track']}: {label}{detail}")
    return ", ".join(parts) or "none given"


def listing(values, other=None):
    items = [value.replace("_", " ") for value in values or []]
    if other:
        items.append(other)
    return ", ".join(items) or "none given"


def checkins(person):
    text = {"1_2": "1 to 2 a month", "3_4": "3 to 4 a month", "flexible": "flexible"}[person["availability"]]
    return f"{text} ({person['availability_other']})" if person.get("availability_other") else text


def mentee_profile(mentee, labels):
    lines = [
        f"Class: {mentee['class_level']}, board: {mentee['board_other'] or mentee['board']}",
        f"Fields: {listing(mentee['tracks'])}, target year {mentee['target_year']}",
        f"Wants help with: {help_areas(mentee['mentee_help_areas'], labels)}",
        f"Subjects: {listing(mentee['subjects'], mentee['subjects_other'])}",
        f"Languages: {listing(mentee['language_preferences'], mentee['language_other'])}",
        f"Check-ins: {checkins(mentee)}",
        f"In their words: {mentee['help_in']}",
    ]
    if mentee.get("additional_info"):
        lines.append(f"Also: {mentee['additional_info']}")
    return "\n".join(lines)


def mentor_profile(mentor, labels):
    lines = [
        f"Now: {mentor['current_status']}",
        f"Board: {mentor['board_other'] or mentor['board']}",
        f"Fields: {listing(mentor['tracks'])}",
        f"Mentors classes: {listing(mentor['mentee_levels'])}",
        f"Can help with: {help_areas(mentor['mentor_help_areas'], labels)}",
        f"Subjects: {listing(mentor['subjects'], mentor['subjects_other'])}",
        f"Results: {mentor['exam_results'] or 'none given'}",
        f"Languages: {listing(mentor['language_preferences'], mentor['language_other'])}",
        f"Check-ins: {checkins(mentor)}",
    ]
    if mentor.get("abroad_details"):
        lines.append(f"Abroad: {mentor['abroad_details']}")
    if mentor.get("additional_info"):
        lines.append(f"Also: {mentor['additional_info']}")
    return "\n".join(lines)


def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def refresh_embeddings(db, encoder, table, key, people, profiles):
    ids = [person["id"] for person in people]
    if not ids:
        return
    stored = db.table(table).select(f"{key}, created_at").in_(key, ids).execute().data
    embedded_at = {row[key]: parse_time(row["created_at"]) for row in stored}
    stale = [
        person for person in people
        if person["id"] not in embedded_at or parse_time(person["updated_at"]) > embedded_at[person["id"]]
    ]
    if not stale:
        return
    vectors = encoder.encode([profiles[person["id"]] for person in stale], normalize_embeddings=True)
    rows = [
        {key: person["id"], "embedding": vector.tolist(), "model": EMBED_MODEL, "created_at": datetime.now().astimezone().isoformat()}
        for person, vector in zip(stale, vectors)
    ]
    db.table(table).upsert(rows, on_conflict=key).execute()
    print(f"embedded {len(rows)} rows into {table}")


def choose(generator, mentee_text, candidates):
    mentors = "\n\n".join(f"Candidate {i}:\n{text}" for i, (_, text, _) in enumerate(candidates, 1))
    messages = [{"role": "user", "content": PROMPT.format(mentee=mentee_text, mentors=mentors, count=len(candidates))}]
    reply = generator(messages, max_new_tokens=200, do_sample=False, return_full_text=False)[0]["generated_text"]
    found = re.search(r"\{.*\}", reply, re.DOTALL)
    if not found:
        return None
    try:
        answer = json.loads(found.group(0))
        index = int(answer["choice"]) - 1
        confidence = min(max(float(answer["confidence"]), 0.0), 1.0)
    except (ValueError, KeyError, TypeError):
        return None
    if not 0 <= index < len(candidates):
        return None
    return candidates[index][0], confidence, str(answer.get("reason", "")).strip()[:1000]


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--cohort", type=int, required=True)
    parser.add_argument("--top-k", type=int, default=8)
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    from sentence_transformers import SentenceTransformer
    from transformers import pipeline

    db = connect()
    labels = area_labels(db)

    mentees = load(db, "mentees", args.cohort, "*, mentee_help_areas (track, area, area_other)")
    mentors = load(db, "mentors", args.cohort, "*, mentor_help_areas (track, area, area_other)")
    mentee_texts = {m["id"]: mentee_profile(m, labels) for m in mentees}
    mentor_texts = {m["id"]: mentor_profile(m, labels) for m in mentors}
    mentor_by_id = {m["id"]: m for m in mentors}

    encoder = SentenceTransformer(EMBED_MODEL, trust_remote_code=True, device="cuda")
    refresh_embeddings(db, encoder, "mentee_embeddings", "mentee_id", mentees, mentee_texts)
    refresh_embeddings(db, encoder, "mentor_embeddings", "mentor_id", mentors, mentor_texts)

    live = db.table("assignments").select("mentee_id, mentor_id").eq("cohort_id", args.cohort).in_("status", LIVE).execute().data
    assigned_mentees = {row["mentee_id"] for row in live}
    load_by_mentor = Counter(row["mentor_id"] for row in live)

    generator = pipeline("text-generation", model=CHAT_MODEL, device_map="auto", torch_dtype="bfloat16")

    made = 0
    for mentee in mentees:
        if mentee["id"] in assigned_mentees:
            continue
        stored = db.table("mentee_embeddings").select("embedding").eq("mentee_id", mentee["id"]).single().execute().data
        matches = db.rpc("match_mentors", {
            "query_embedding": stored["embedding"],
            "match_cohort_id": args.cohort,
            "match_count": args.top_k * 2,
        }).execute().data

        candidates = [
            (match["mentor_id"], mentor_texts[match["mentor_id"]], match["similarity"])
            for match in matches
            if match["mentor_id"] in mentor_by_id
            and mentee["class_level"] in mentor_by_id[match["mentor_id"]]["mentee_levels"]
            and load_by_mentor[match["mentor_id"]] < mentor_by_id[match["mentor_id"]]["mentor_capacity"]
        ][: args.top_k]
        if not candidates:
            print(f"mentee {mentee['id']}: no mentor with free capacity for their class")
            continue

        picked = choose(generator, mentee_texts[mentee["id"]], candidates)
        if not picked:
            print(f"mentee {mentee['id']}: model reply unusable, skipped")
            continue

        mentor_id, confidence, reason = picked
        print(f"mentee {mentee['id']} -> mentor {mentor_id} ({confidence:.2f}): {reason}")
        load_by_mentor[mentor_id] += 1
        made += 1
        if not args.dry_run:
            db.table("assignments").insert({
                "cohort_id": args.cohort,
                "mentee_id": mentee["id"],
                "mentor_id": mentor_id,
                "confidence_score": confidence,
                "reason": reason,
            }).execute()

    print(f"{'proposed' if args.dry_run else 'created'} {made} pending assignments")


if __name__ == "__main__":
    main()
