import { HttpError } from "./http.js";

const signOff = "- The Peer Project Team";

function istDate(value) {
  return new Date(value).toLocaleString("en-IN", {
    timeZone: "Asia/Kolkata",
    dateStyle: "long",
    timeStyle: "short",
  });
}

function cohortTitle(name) {
  return name.charAt(0).toUpperCase() + name.slice(1);
}

const proofDeleted = "Your proof of eligibility has been deleted from our storage, as promised.";
const discordInvite = Deno.env.get("DISCORD_INVITE");

const decisions = {
  mentor: {
    accepted: (cohort) => ({
      subject: `TPP // you're mentoring in ${cohort}`,
      body: [
        `We'd like you to mentor in ${cohort}. Thanks for applying, and for the time you put into the questionnaire.`,
        "We'll reach out on Discord once we've matched you with a mentee, so keep an eye on the server. Until then, have a read of the mentor guide if you haven't: peerproject.in/mentorguide",
        proofDeleted,
      ],
    }),
    rejected: (cohort) => ({
      subject: "TPP // about your mentor application",
      body: [
        `We won't be taking you on as a mentor for ${cohort}. We had to make some hard calls this time, and it didn't go your way.`,
        "Thanks for applying though, and for the time you put into the questionnaire. You're welcome to apply again next cohort, we'll announce it on the site and our subreddits.",
        proofDeleted,
      ],
    }),
  },
  mentee: {
    accepted: (cohort) => ({
      subject: `TPP // you're in for ${cohort}`,
      body: [
        `You're in for ${cohort}. We'll message you on Discord once we've matched you with a mentor, so make sure you're on our server${discordInvite ? `: ${discordInvite}` : "."}`,
        "Until then, the mentee guide covers what to expect: peerproject.in/menteeguide",
      ],
    }),
    waitlisted: (cohort) => ({
      subject: `TPP // you're on the ${cohort} waitlist`,
      body: [
        `We don't have a mentor who fits what you need just yet, so you're on the waitlist for ${cohort}. It's not a no. Mentors do free up during the cohort, and if one does, we'll email you.`,
        "In the meantime, our resource directory is open to everyone: peerproject.in/resources",
      ],
    }),
    rejected: (cohort) => ({
      subject: `TPP // about your ${cohort} application`,
      body: [
        `We can't take you on for ${cohort}. We had to make some hard calls this time, and couldn't fit you in.`,
        "You're welcome to apply again next cohort, we'll announce it on the site and our subreddits. In the meantime, our resource directory is open to everyone: peerproject.in/resources",
      ],
    }),
  },
};

export function decisionMail(kind, status, person) {
  const build = decisions[kind]?.[status];
  if (!build) return null;
  const { subject, body } = build(cohortTitle(person.cohort));
  return { to: person.email, subject, text: [`Hey ${person.display_name},`, ...body, signOff].join("\n\n") };
}

export function questionnaireMail(person, link, expiresAt) {
  return {
    to: person.email,
    subject: "TPP // your mentor questionnaire",
    text: [
      `Hey ${person.display_name},`,
      "Here's the link to your mentor questionnaire:",
      link,
      `It works until ${istDate(expiresAt)} IST. It's 8 situations our mentors actually ran into last cohort, and what you'd do in each. It isn't really about right or wrong answers, but it does matter a lot in whether you get picked, so do give it some thought.`,
      "This link is yours, so keep it to yourself. If you lose it, you can get a new one at peerproject.in/questionnaire.",
      signOff,
    ].join("\n\n"),
  };
}

export function lockoutMail(to, address, ip, lockedUntil) {
  return {
    to,
    subject: "Admin sign-in locked after 3 failed attempts",
    text: [
      `Someone failed to sign in to the TPP admin page 3 times as ${address}, so that account is locked until ${istDate(lockedUntil)} IST.`,
      `The last attempt came from IP ${ip ?? "unknown"} at ${istDate(new Date())} IST.`,
      "If this was you, just wait out the hour. If it wasn't, change that account's password in Supabase (Authentication, Users) and tell the other admins.",
      "- TPP admin page",
    ].join("\n\n"),
  };
}

export function probeMail(to, count, ips) {
  return {
    to,
    subject: "Someone is trying emails on the admin sign-in",
    text: [
      count === 1
        ? "1 email that isn't an admin account got locked on the TPP admin page in the last 24 hours, after 3 failed sign-in attempts."
        : `${count} emails that aren't admin accounts got locked on the TPP admin page in the last 24 hours, after 3 failed sign-in attempts each.`,
      `IPs: ${ips.slice(0, 20).join(", ")}${ips.length > 20 ? `, and ${ips.length - 20} more` : ""}.`,
      "None of them are admin accounts, so nobody got in. This could just be someone mistyping, but if it keeps happening, it's worth switching on CAPTCHA for sign-in in Supabase (Authentication, Attack Protection). You'll get at most one of these a day.",
      "- TPP admin page",
    ].join("\n\n"),
  };
}

export async function sendMail({ to, subject, text }) {
  const response = await fetch("https://api.resend.com/emails", {
    method: "POST",
    headers: {
      authorization: `Bearer ${Deno.env.get("RESEND_API_KEY")}`,
      "content-type": "application/json",
    },
    body: JSON.stringify({ from: Deno.env.get("MAIL_FROM"), to, subject, text }),
  });
  if (!response.ok) {
    console.error("resend", response.status, await response.text());
    throw new HttpError(502, "mail_failed");
  }
}
