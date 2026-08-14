from pathlib import Path

import torch
from pydantic import BaseModel, Field
from transformers import (
    AutoTokenizer,
    AutoModelForCausalLM,
    pipeline,
)

from langchain_huggingface import HuggingFacePipeline
from langchain_core.prompts import PromptTemplate
from langchain_core.output_parsers import PydanticOutputParser


class MentorMatch(BaseModel):
    mentor_id: str = Field(description="Discord ID of the selected mentor")
    mentee_id: str = Field(description="Discord ID of the mentee")
    confidence_score: float = Field(
        ge=0.0,
        le=1.0,
        description="Confidence in the match, from 0 to 1"
    )
    reason: str = Field(description="Reason for the mentor-mentee match")


class Gemma:

    MODEL_NAME = "google/gemma-3-4b-it"

    # --------------------------------------------------
    # Prompt
    # --------------------------------------------------

    _prompt_path = (
        Path(__file__).resolve().parents[1]
        / "prompts"
        / "mentor_match.txt"
    )

    _prompt_text = _prompt_path.read_text(
        encoding="utf-8"
    )

    _parser = PydanticOutputParser(
        pydantic_object=MentorMatch
    )

    _prompt = PromptTemplate(
        template=_prompt_text,
        input_variables=[
            "menteeProfile",
            "mentorProfiles",
        ],
        partial_variables={
            "format_instructions": _parser.get_format_instructions()
        },
    )

    # --------------------------------------------------
    # Model
    # --------------------------------------------------

    _tokenizer = AutoTokenizer.from_pretrained(
        MODEL_NAME
    )

    _model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME,
        torch_dtype=torch.bfloat16,
        device_map="auto",
    ).eval()

    _generation_pipeline = pipeline(
        "text-generation",
        model=_model,
        tokenizer=_tokenizer,
        max_new_tokens=256,
        do_sample=False,
        return_full_text=False,
    )

    _llm = HuggingFacePipeline(
        pipeline=_generation_pipeline
    )

    # --------------------------------------------------
    # Mentor Matching
    # --------------------------------------------------

    @classmethod
    def match_mentor(
        cls,
        mentee_profile,
        mentor_profiles,
    ) -> MentorMatch:

        prompt = cls._prompt.format(
            menteeProfile=mentee_profile,
            mentorProfiles=mentor_profiles,
        )

        response = cls._llm.invoke(prompt)

        return cls._parser.parse(response)