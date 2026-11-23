import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Note-Taking App for Students & Study Notes",
  description: "Explore Snotee for handwritten study notes, digital notebooks, PDF reading, and revision workflows. A free, open-source, local-first notes app.",
  alternates: { canonical: "https://snotee.vercel.app/student-note-taking-app" }
};

export default function StudentNotesPage() {
  return <SearchLanding
    path="/student-note-taking-app"
    eyebrow="STUDENT NOTE-TAKING"
    title="Note-taking app for students."
    accent="Built around focused study."
    intro="Snotee is a free, open-source note-taking app for students who combine handwritten notes, diagrams, reading, and digital study material. Keep notebook work local-first, and check the current release for the exact features available on your device."
    sections={[
      { title: "Handwritten class and revision notes", body: "Use a notebook-style writing surface to capture explanations, diagrams, formulas, and revision points. Stylus behavior and pressure response depend on your tablet, pen hardware, and app version.", bullets: ["Handwritten notes and diagrams", "Stylus-oriented writing tools", "Organize study material into notebooks"] },
      { title: "Read and work alongside PDFs", body: "Keep document reading and note-taking in the same study workflow. Before relying on a specific PDF feature, verify import, annotation persistence, and export behavior in the release you install.", bullets: ["PDF reading workflows", "Study notes alongside reference material", "Check release notes for platform-specific PDF support"] },
      { title: "Keep your study notes under your control", body: "Snotee follows a local-first approach for core note-taking. Make regular backups and test restoring them; an app update is not a substitute for a backup.", bullets: ["Local-first note storage", "No mandatory hosted account for core notes", "Public source code and release history"] }
    ]}
    faqs={[
      { question: "What should students look for in a note-taking app?", answer: "Look for reliable handwriting, clear organization, PDF compatibility, export and backup options, and performance on your actual device. Test the workflows you use most before moving all your notes." },
      { question: "Is Snotee a good note-taking app for students using Android tablets?", answer: "Snotee targets Android and includes handwriting and document workflows. Stylus compatibility and PDF capabilities vary by device and release, so test the current APK first." },
      { question: "Can I use Snotee offline?", answer: "Snotee is designed as a local-first application. Check the current version's behavior for any optional integrations, and keep a separate backup." },
      { question: "Is Snotee free and open source?", answer: "The project is published under the MIT license and offers free release downloads. Review the repository license and current release assets for details." }
    ]}
  />;
}
