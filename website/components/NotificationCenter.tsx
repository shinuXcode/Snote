"use client";

import { useEffect, useState } from "react";
import Icon from "./Icon";

type Notice = { id: string; title: string; body: string; date: string | null; href: string; kind: string };

export default function NotificationCenter() {
  const [open, setOpen] = useState(false);
  const [items, setItems] = useState<Notice[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");

  useEffect(() => {
    if (!open || items.length) return;
    let active = true;
    setLoading(true);
    fetch("/api/notifications", { cache: "no-store" })
      .then(async response => {
        if (!response.ok) throw new Error("Notifications are temporarily unavailable.");
        return response.json();
      })
      .then(data => { if (active) setItems(data.notifications ?? []); })
      .catch(err => { if (active) setError(err instanceof Error ? err.message : "Could not load updates."); })
      .finally(() => { if (active) setLoading(false); });
    return () => { active = false; };
  }, [open, items.length]);

  return <div className="notification-wrap">
    <button className="icon-button notification-trigger" aria-label="Open notification centre" aria-expanded={open} onClick={() => setOpen(value => !value)}>
      <Icon name="bell" size={18} /><span className="notification-dot" />
    </button>
    {open && <section className="notification-panel" aria-label="Notification centre">
      <div className="notification-head"><div><span className="eyebrow">SNOTE UPDATES</span><h2>Notification centre</h2></div><button className="icon-button small-icon" aria-label="Close notifications" onClick={() => setOpen(false)}><Icon name="close" size={16}/></button></div>
      <p className="notification-intro">Release announcements and project updates, pulled from GitHub.</p>
      {loading && <p className="muted">Loading latest updates…</p>}
      {error && <p className="notification-error">{error}</p>}
      {!loading && !error && items.length === 0 && <p className="muted">No published updates yet.</p>}
      <div className="notification-list">{items.map(item => <a className="notification-item" href={item.href} target="_blank" rel="noreferrer" key={item.id}>
        <span className="notification-kind">{item.kind}</span><strong>{item.title}</strong><span className="muted">{item.body}</span><small>{item.date ? new Date(item.date).toLocaleDateString() : "Snote project update"} <Icon name="external" size={12}/></small>
      </a>)}</div>
      <a className="notification-all" href="https://github.com/shinuXcode/Snote/releases" target="_blank" rel="noreferrer">All GitHub releases <Icon name="arrow" size={14}/></a>
    </section>}
  </div>;
}
