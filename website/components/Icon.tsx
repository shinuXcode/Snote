import type { SVGProps } from "react";
type IconName = "pen" | "organize" | "open" | "flow" | "fast" | "cube" | "lock" | "sun" | "moon" | "github" | "arrow" | "external" | "menu" | "close" | "sparkles" | "link" | "lightbulb" | "download" | "check" | "refresh" | "bell" | "message";
const common: SVGProps<SVGSVGElement> = { viewBox: "0 0 24 24", fill: "none", stroke: "currentColor", strokeWidth: 1.65, strokeLinecap: "round", strokeLinejoin: "round", "aria-hidden": true, focusable: false };
export default function Icon({ name, size = 20, className }: { name: IconName; size?: number; className?: string }) {
 const shapes: Record<IconName, React.ReactNode> = {
  pen:<><path d="m4 16.5 10.9-10.9a2.1 2.1 0 0 1 3 3L7 19.5 3 21z"/><path d="m13.5 7.5 3 3M3 21l4-1.5M18 3l3 3"/></>,
  organize:<><path d="m12 2 9 5v10l-9 5-9-5V7z"/><path d="m3.2 7.2 8.8 5 8.8-5M12 22V12.2"/></>,
  open:<><path d="M10 13.5a4.5 4.5 0 0 0 6.4 0l3.1-3.1a4.5 4.5 0 0 0-6.4-6.4l-1.8 1.8"/><path d="M14 10.5a4.5 4.5 0 0 0-6.4 0l-3.1 3.1a4.5 4.5 0 0 0 6.4 6.4l1.8-1.8"/></>,
  flow:<><circle cx="12" cy="12" r="3"/><path d="M12 2v4m0 12v4M2 12h4m12 0h4M4.9 4.9l2.8 2.8m8.6 8.6 2.8 2.8m0-14.2-2.8 2.8m-8.6 8.6-2.8 2.8"/></>,
  fast:<><path d="m13 2-9 12h7l-1 8 10-13h-7z"/></>, cube:<><path d="m12 2 9 5v10l-9 5-9-5V7z"/><path d="m3.2 7.2 8.8 5 8.8-5M12 22V12.2"/></>,
  lock:<><rect x="4" y="10" width="16" height="12" rx="2"/><path d="M8 10V7a4 4 0 0 1 8 0v3"/><path d="M12 14v4"/></>,
  sun:<><circle cx="12" cy="12" r="4"/><path d="M12 2v2m0 16v2M4.93 4.93l1.42 1.42m11.3 11.3 1.42 1.42M2 12h2m16 0h2M4.93 19.07l1.42-1.42m11.3-11.3 1.42-1.42"/></>,
  moon:<path d="M20.8 14.1A8.5 8.5 0 0 1 9.9 3.2 8.7 8.7 0 1 0 20.8 14.1Z"/>,
  github:<path fill="currentColor" stroke="none" d="M12 .297c-6.63 0-12 5.373-12 12 0 5.303 3.438 9.8 8.205 11.385.6.113.82-.258.82-.577 0-.285-.01-1.04-.015-2.04-3.338.726-4.042-1.61-4.042-1.61-.546-1.387-1.333-1.756-1.333-1.756-1.09-.745.083-.729.083-.729 1.205.085 1.84 1.237 1.84 1.237 1.07 1.835 2.807 1.305 3.492.998.108-.776.418-1.305.762-1.605-2.665-.304-5.467-1.334-5.467-5.931 0-1.31.468-2.381 1.235-3.221-.124-.303-.535-1.524.117-3.176 0 0 1.008-.323 3.3 1.23a11.48 11.48 0 0 1 6.006 0c2.29-1.553 3.295-1.23 3.295-1.23.655 1.652.244 2.873.824.576C20.565 22.092 24 17.596 24 12.297c0-6.627-5.373-12-12-12Z"/>,
  arrow:<><path d="M5 12h14"/><path d="m13 6 6 6-6 6"/></>, external:<><path d="M14 3h7v7"/><path d="M10 14 21 3"/><path d="M19 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7a2 2 0 0 1 2-2h6"/></>,
  menu:<><path d="M4 7h16M4 12h16M4 17h16"/></>, close:<><path d="m6 6 12 12M18 6 6 18"/></>,
  sparkles:<><path d="m12 3 1.8 5.2L19 10l-5.2 1.8L12 17l-1.8-5.2L5 10l5.2-1.8z"/><path d="m19 15 .9 2.1L22 18l-2.1.9L19 21l-.9-2.1L16 18l2.1-.9z"/></>,
  link:<><path d="M10 13.5a4.5 4.5 0 0 0 6.4 0l3.1-3.1a4.5 4.5 0 0 0-6.4-6.4l-1.8 1.8"/><path d="M14 10.5a4.5 4.5 0 0 0-6.4 0l-3.1 3.1a4.5 4.5 0 0 0 6.4 6.4l1.8-1.8"/></>,
  lightbulb:<><path d="M9 18h6m-5 4h4"/><path d="M8.3 14.5A6 6 0 1 1 15.7 14.5c-.9.7-1.2 1.5-1.2 2.5h-5c0-1-.3-1.8-1.2-2.5Z"/></>,
  download:<><path d="M12 3v12m-5-5 5 5 5-5"/><path d="M4 17v4h16v-4"/></>, check:<path d="m5 12 4 4L19 6"/>,
  refresh:<><path d="M20 7v5h-5"/><path d="M4 17v-5h5"/><path d="M5.6 9A7 7 0 0 1 17.5 6L20 12M4 12l2.5 6A7 7 0 0 0 18.4 15"/></>,
  bell:<><path d="M18 8a6 6 0 0 0-12 0c0 7-3 7-3 9h18c0-2-3-2-3-9"/><path d="M10 21h4"/></>,
  message:<><path d="M21 11.5a8.4 8.4 0 0 1-.9 3.8 8.5 8.5 0 0 1-7.6 4.7 8.4 8.4 0 0 1-3.8-.9L3 21l1.9-5.7a8.4 8.4 0 0 1-.9-3.8A8.5 8.5 0 0 1 8.7 3.9a8.4 8.4 0 0 1 3.8-.9h.5a8.5 8.5 0 0 1 8 8z"/></>
 };
 return <svg {...common} width={size} height={size} className={className}>{shapes[name]}</svg>;
}
