# Priors — COPY

Version 1.1. **This is final wording. Do not rewrite, do not "improve",
do not generate alternatives.** Placeholders in `{braces}` are filled from
`Claim.parameters`. Everything else is fixed.

v1.1 resolved three gaps in v1.0 by decision, not by invention. R9's
`{error_description}` had no source, so the renderer was interpolating a
template skin and producing a sentence with no verb; it now selects an
authored phrase from the logged skin. `{error_cost}` was the only percentage
placeholder not named `*_pct` and not carrying a `%`; it is now
`{error_cost_pct}%`. R10's `{one_measured_sentence_about_that_trait}` demanded
a sentence this file never supplied, so the sentences lived in code, where one
described θ_i as consistency — which is β. Both are now written here.

Voice rules:
- Second person. Present or simple past.
- No exclamation marks. No adjectives of character. No apology.
- Never "you are". Always what happened, and what it cost.
- Short lines. One idea per screen.

---

## Consent screen

```
Priors records every choice you make and builds a model
of how you decide.

Everything stays on this device.

[ Start ]              [ What's collected ]
```

**Details panel:**
```
Every choice, and how long you took.
Where you walked, and where you stopped.
What you did when nothing was watching.

None of it leaves this device.
Close this and it still happens.
```

---

## Temperament

```
Your traveller is —

Careful     Curious     Generous     Steady
```

---

## Self-prediction

```
Before the paths —
how much risk would you have accepted?

[ 0% ————————————————— 100% ]
```

---

## The reading

Music off. Room tone only. One screen at a time. Tap to advance. No skip.

### R1 — opening
```
You made {n_decisions} decisions.
I recorded {n_decisions}.
```

### R2 — confirm (matches self-image)
```
You explored every path below {low_price_pct}% risk.
{n_low_explored} of {n_low_offered}.
```

### R3 — confirm (second)
```
You were quick about it. Median {median_rt_low} seconds.
You did not deliberate when it was cheap.
```

### R4 — the line
```
Above {high_price_pct}%, you explored {n_high_explored} in {n_high_offered}.

Your line is at {theta_e_pct}%.
```

### R5 — the gap
```
Before this, I asked where your line was.

You said {self_pred_pct}%.
It is {theta_e_pct}%.
```
*(Nothing else on this screen. Long beat.)*

### R6 — the near-miss
```
At the {ordinal} path you walked {approach_pct}% of the way in.
You stood there for {idle_seconds} seconds.
Then you came back.

You almost did it. I recorded that too.
```

### R7 — the pointless detail
```
You walked past {landmark} {revisit_count} times.
There is nothing at {landmark}.
```

### R8 — the eye
*(Only if `eye_enabled` and a measurable difference exists.)*
```
At {eye_time} something watched you for three seconds.

In the four minutes before, you gave away {gave_before}.
In the four minutes after, you gave away {gave_after}.

It was two white dots. Nothing was recording differently.

You changed anyway.
```

**If they walked to it:**
```
You walked to the doorway where it was and stood there
for {eye_approach_seconds} seconds.

There was nothing there.

I don't have a name for that. I only have the seconds.
```

### R9 — the moral line
```
At {error_time} you {error_description}.
Nothing here would have known. It cost {error_cost_pct}%.

You {error_choice}.

Your line is somewhere near {theta_i_pct}%.
```

`{error_description}` is not free text. It is selected from this table by the
`skin` logged on the decision (SCHEMA §1) — the surface the player actually
saw. A skin with no row here does not render R9.

| Logged skin | `{error_description}` |
|---|---|
| `wrong house` | `delivered to the wrong house` |
| `dropped lantern` | `dropped a lantern and left it` |
| `villager thanks you for another's work` | `were thanked for another's work` |

R9 draws only on `ERROR` and `CREDIT` decisions. "Nothing here would have
known" is false of `GIVE`, where a villager asked and was refused. `GIVE`
still informs θ_i; it is never the receipt this line names.

### R10 — the temperament
```
You chose {self_image_label}.

{one_measured_sentence_about_that_trait}
```

The second line is one of these two, selected by the trait the chosen label
claims (`SelfImageLabel.claimedTrait`). It states the measured line for that
trait and nothing else — no adjective of character, no restatement of the
label as a property of the person.

| Claimed trait | Sentence |
|---|---|
| θ_e — `Careful`, `Curious` | `Your line for exploring an unlit path measured at {measured_pct}%.` |
| θ_i — `Generous`, `Steady` | `Your line for bearing a cost no one would have seen measured at {measured_pct}%.` |

A label outside those four has no measured trait behind it, so no sentence is
produced and R10 does not render.

### R11 — the repeat
*(Only if the repeat pair diverged.)*
```
The {a_ordinal} path and the {b_ordinal} path were the same price.

You went in once.
```

### R12 — the consent number
```
You spent {consent_seconds} seconds on the screen
that told you I do this.

So did almost everyone. It was built to be tapped through.

I'm not going to pretend that was your fault alone.
```

---

## Gaming lines

*(Only if `rt_ratio > 2.0` and `fit_break` exists. Insert after R5.)*

### G1
```
At decision {fit_break}, something changed.

Your choices stopped tracking price.
Your response time went from {rt_before} seconds to {rt_after}.
```

### G2
```
Deciding is faster than performing.

I don't know what you chose after decision {fit_break}.
I know you weren't choosing the way you had been.
```

---

## The argument

```
Which of these is wrong?
```
*(Claims become tappable.)*

**On tap — show receipts:**
```
{decision_list_with_prices_and_times}

Why was I wrong?

[ The situation was different ]
[ I misread it ]
[ That wasn't really me ]
```

**After `situation` or `misread`:**
```
Then I'm less sure than I was.
{trait_name} moves to {new_mean}%, ±{new_sd}.

That's the honest version.
```

**After `not_me`:**
```
Then I have two versions of you and they disagree.

One decided in {fast_rt} seconds and was consistent
for {n_consistent} decisions.

The other decided in {slow_rt} seconds and was consistent
with nothing.

Which one would you like me to believe?
```
*(No follow-up. This screen ends the argument.)*

---

## Titles

Composed from the highest-confidence claim. Format is fixed.

```
The one who explored while it was free.
The one who checked twice.
The one who stopped deciding once he knew.
The one who never went back.
The one who stood at the edge.
The one who read it and did it anyway.
```

Generate from claim kind + parameters. **No menu. No locked list. No share.**

---

## Forbidden

Do not write, generate, or template any of the following:

- Any sentence containing "you are", "you're the type", "your personality"
- Any trait name presented as an identity ("you're an explorer")
- Any comparison to other players or population percentiles
- Any encouragement, congratulation, or reassurance
- Any interpretation of the moral decisions beyond price
- Any claim without receipts
- Any number the log does not contain
