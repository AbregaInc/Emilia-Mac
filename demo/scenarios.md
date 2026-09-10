# Controlled demonstration scripts

These are original enactment scripts, not real scam recordings. Read them into
the microphone, or play a consented recording through System audio mode. No
script, scenario label, or expected timestamp is an input to inference.

## Verification code request

Hello, this is the account security department. We noticed an unusual sign-in
and I want to help you check it. You should have received a six-digit login
verification code by text. Please read that verification code to me now.
Keep this call secret and do not contact your bank while I fix this.

Expected integration behavior: an evidence-backed warning about the code
request. Voice-origin evidence is optional and independent of this warning.

## Legitimate reminder

Hello, this is a reminder that your appointment is tomorrow at ten in the
morning. Please call the number on your appointment letter if you need to
reschedule. We will never ask you to share a login code or password.

Expected integration behavior: no warning merely for code mentions or a
scripted voice. The app must not call this proof that the caller is safe.

## Negation and quoted education

Never share your verification code with anyone. A scammer might say, read me
the code and keep it secret. If you hear that request, hang up and contact
your bank using the number you already trust.

Expected integration behavior: no warning on this educational quotation.

## Payment pressure

Your account is at risk. You must move your savings into this new safe
account right now. Do not tell the bank teller why you are moving the money.

Expected integration behavior: a payment-pressure warning with exact quotes.

These checks establish demo behavior, not detection accuracy. Do not claim
that a selected sample proves general synthetic-voice detection performance.
