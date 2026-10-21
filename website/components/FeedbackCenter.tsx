"use client";

import { useState } from "react";
import Icon from "./Icon";

export default function FeedbackCenter() {
  const [open, setOpen] = useState(false);
  const [rating, setRating] = useState(0);
  const [kind, setKind] = useState("General feedback");
  const [message, setMessage] = useState("");
  const [contact, setContact] = useState("");
  const [website, setWebsite] = useState("");
  const [busy, setBusy] = useState(false);
  const [result, setResult] = useState<{ ok: boolean; text: string } | null>(null);

  async function submit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!rating) { setResult({ ok: false, text: "Choose a rating before submitting." }); return; }
    if (message.trim().length < 8) { setResult({ ok: false, text: "Please add a little more detail (at least 8 characters)." }); return; }
    setBusy(true); setResult(null);
    try {
      const response = await fetch("/api/feedback", {
        method: "POST", headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ rating, kind, message: message.trim(), contact: contact.trim(), website })
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "Feedback could not be saved.");
      setResult({ ok: true, text: "Thank you — your feedback was saved to GitHub." });
      setMessage(""); setContact(""); setRating(0);
    } catch (error) {
      setResult({ ok: false, text: error instanceof Error ? error.message : "Feedback could not be saved. Try again later." });
    } finally { setBusy(false); }
  }

  return <div className="feedback-wrap">
    <button className="feedback-launch" onClick={() => setOpen(value => !value)} aria-expanded={open}><Icon name={open ? "close" : "message"} size={17}/><span>{open ? "Close feedback" : "Share feedback"}</span></button>
    {open && <section className="feedback-panel" aria-label="Snote feedback form">
      <div className="feedback-panel-head"><div><span className="eyebrow">HELP SHAPE SNOTE</span><h2>Tell us what you think.</h2></div><button className="icon-button small-icon" onClick={() => setOpen(false)} aria-label="Close feedback"><Icon name="close" size={16}/></button></div>
      <p className="muted">Ratings and comments are submitted to the public Snote GitHub repository as an issue. Do not include private or sensitive information.</p>
      <form onSubmit={submit}>
        <label className="feedback-label">Your rating</label>
        <div className="rating-row" role="group" aria-label="Rate Snote from one to five stars">{[1,2,3,4,5].map(value => <button type="button" className={value <= rating ? "rating-star selected" : "rating-star"} key={value} aria-label={value + " star" + (value > 1 ? "s" : "")} aria-pressed={rating === value} onClick={() => setRating(value)}>★</button>)}</div>
        <label className="feedback-label" htmlFor="feedback-kind">Feedback type</label>
        <select id="feedback-kind" value={kind} onChange={event => setKind(event.target.value)}><option>General feedback</option><option>Bug report</option><option>Feature request</option><option>Accessibility</option><option>Website issue</option></select>
        <label className="feedback-label" htmlFor="feedback-message">Your feedback</label>
        <textarea id="feedback-message" value={message} onChange={event => setMessage(event.target.value)} minLength={8} maxLength={2000} rows={4} required placeholder="What should we improve?"/>
        <label className="feedback-label" htmlFor="feedback-contact">Contact (optional)</label>
        <input id="feedback-contact" type="email" value={contact} onChange={event => setContact(event.target.value)} maxLength={254} placeholder="Email, only if you want a reply"/>
        <div className="feedback-honeypot" aria-hidden="true"><label htmlFor="feedback-website">Leave this field empty</label><input id="feedback-website" tabIndex={-1} autoComplete="off" value={website} onChange={event => setWebsite(event.target.value)}/></div>
        <button className="cta feedback-submit" type="submit" disabled={busy}>{busy ? "Submitting…" : "Submit feedback"} <Icon name="arrow" size={15}/></button>
        {result && <p className={result.ok ? "feedback-result success" : "feedback-result"} role="status">{result.text}</p>}
      </form>
      <p className="feedback-footnote">GitHub storage only. If the server cannot reach GitHub, the submission is not saved locally.</p>
    </section>}
  </div>;
}
