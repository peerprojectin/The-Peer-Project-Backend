from App.AI.models.gemma import Gemma


mentee = """
Discord ID: mentee_001

Academic Stage: Grade 12

Career Goal: Computer Science

Interests:
- Artificial Intelligence
- Machine Learning
- Competitive Programming

Mentorship Needs:
- Guidance about pursuing Computer Science
- Advice about competitive programming
- Help understanding university applications
"""


mentors = """
MENTOR 1

Discord ID: mentor_001
Academic Background: Computer Science
Experience:
- Competitive programming
- Machine learning projects
- University application process
Interests:
- AI
- Software Engineering


MENTOR 2

Discord ID: mentor_002
Academic Background: Mechanical Engineering
Experience:
- Robotics
- CAD
- Mechanical design
Interests:
- Motorsports
- Robotics


MENTOR 3

Discord ID: mentor_003
Academic Background: Computer Science
Experience:
- Web development
- Frontend development
- UI/UX
Interests:
- Web design
- Startups
"""


result = Gemma.match_mentor(
    mentee_profile=mentee,
    mentor_profiles=mentors
)

print("\n========== GEMMA RESULT ==========\n")

print("Mentor ID:", result.mentor_id)
print("Mentee ID:", result.mentee_id)
print("Confidence:", result.confidence_score)
print("Reason:", result.reason)