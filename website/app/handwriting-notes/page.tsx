import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Handwriting Notes App for Android & Stylus",
  description: "Explore Snotee, a handwriting notes app for Android tablets and stylus workflows. Write study notes, sketch ideas, and keep notebooks local-first.",
  alternates: { canonical: "https://snotee.vercel.app/handwriting-notes" }
};

export default function HandwritingNotesPage() {
  return <SearchLanding path="/handwriting-notes" eyebrow="DIGITAL HANDWRITING" title="Handwriting notes." accent="Made for stylus workflows." intro="Snotee is an open-source handwriting notes app for digital notebooks, handwritten study notes, and stylus-first workflows. Its custom writing surface is designed for pen input, while real pressure response and palm rejection depend on the device and published app version." sections={[
    { title: "A writing surface, not a web form", body: "The app is built with Flutter and includes a dedicated canvas and ink pipeline. Its goal is to make strokes appear naturally while keeping the page stable during writing, scrolling, and zooming.", bullets: ["Custom canvas and stroke rendering", "Pen and eraser workflows", "Notebook page and canvas concepts"] },
    { title: "Stylus behavior depends on hardware", body: "Pressure sensitivity, palm rejection, hover, and pen shortcuts are not identical across Android tablets and styluses. Snotee's input handling is designed for pen workflows, but device-specific testing matters.", bullets: ["Pressure-aware ink where hardware exposes it", "Palm-rejection support where the device allows it", "Test with your own pen before moving important work"] },
    { title: "Keep handwritten work portable", body: "Snotee is designed as a local-first application. Use the backup and export options available in your version, and test that a backup restores correctly before removing the original notebook.", bullets: ["Local device storage", "User-controlled backup and transfer", "Open repository and public issue tracker"] }
  ]} faqs={[
    { question: "Is Snotee suitable for handwritten study notes?", answer: "It is designed for handwriting and notebook workflows. Check current release notes and test your device before using it as the only copy of important study material." },
    { question: "Does Snotee support pressure sensitivity?", answer: "The project describes pressure-aware strokes. Actual pressure response depends on stylus hardware, operating system support, and app version." },
    { question: "Does Snotee guarantee zero writing latency?", answer: "No app can guarantee zero latency on every device. Performance depends on display refresh rate, hardware, stylus digitizer, operating system, and rendering load." }
  ]} />;
}
