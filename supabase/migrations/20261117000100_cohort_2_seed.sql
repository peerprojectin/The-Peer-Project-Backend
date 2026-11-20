with cohort as (
  insert into public.cohorts (name, mentee_opens_at, mentor_opens_at)
  values ('cohort 2', '2027-01-01 00:00:00+05:30', '2027-01-01 00:00:00+05:30')
  returning id
)
insert into public.interview_questions (cohort_id, position, prompt)
select cohort.id, q.position, q.prompt
from cohort,
(values
  (1, 'Your mentee started well, then hasn''t replied in 10 days. What do you do, and what exactly would you send them?'),
  (2, 'Your mentee says they''re sleeping about 4 hours a night, feel exhausted all the time, and their parents won''t take them to a doctor. How do you respond?'),
  (3, 'Mid-conversation, your mentee mentions they copied answers in a school test to keep their marks up. What do you say?'),
  (4, 'Your mentee asks you to send them a full study timetable. How do you approach it?'),
  (5, 'Your mentee asks whether you think they have ADHD. How do you answer?'),
  (6, 'Your mentee scored 300 in a mock test and wants 650 in three months. How do you talk about it honestly without crushing them?'),
  (7, 'Your mentee asks to continue on Instagram or WhatsApp instead of the server. What do you do?'),
  (8, 'Halfway through the cohort, your own exams pile up and you can''t keep up with your mentee. What do you do, and when?')
) as q (position, prompt);
