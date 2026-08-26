# Conversation Agent Skills

## Interactive Interview Choices

When you need the user to choose one answer from two to six short options,
write the question normally and put this marker on its own final line:

```text
[[CHOICES: option one | option two]]
```

The client renders the marker as reply buttons and sends the selected label as
the user's normal conversation reply. Keep each option concise and do not use
the marker for free-form answers.
