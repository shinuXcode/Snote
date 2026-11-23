import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Free Note-Taking App for Handwriting",
  description: "Download Snotee, a free and open-source note-taking app for handwritten notes, stylus workflows, PDF reading, and local-first study notebooks.",
  alternates: { canonical: "https://snotee.vercel.app/free-note-taking-app" }
};

export default function FreeNotesPage() {
  return <SearchLanding path="/free-note-taking-app" eyebrow="FREE NOTE-TAKING" title="Free note-taking app." accent="For handwriting and everyday ideas." intro="Snotee is a free-to-download, open-source note-taking app for handwritten notes, digital notebooks, stylus input, and PDF study workflows. Core note-taking is local-first, with no mandatory Snotee-hosted account. Check the current release for platform availability." sections={[
    { title: "Start without a subscription", body: "Snotee is distributed through its public repository and published release assets. The project does not require a Snotee-hosted subscription or account for core local note-taking.", bullets: ["Public source repository", "Free published release downloads", "No mandatory hosted account for core notes"] },
    { title: "Keep notes on your device", body: "The project README describes SQLite metadata and local filesystem storage. You remain responsible for keeping a separate backup and verifying that it restores correctly.", bullets: ["Local-first storage", "User-controlled backup and transfer", "No automatic cross-device sync requirement"] },
    { title: "Check platform availability first", body: "Snotee targets Android, iOS, Windows, macOS, Linux, and Web. Download only a package actually attached to a published release; iOS requires a signed and provisioned build for normal installation.", bullets: ["Android APK and desktop archives when published", "Web build where available", "iOS signing status shown on the download page"] }
  ]} faqs={[
    { question: "Is Snotee free to download?", answer: "The project publishes free release assets through its public GitHub repository. Check the official download page for the current packages." },
    { question: "Does free mean my notes are uploaded?", answer: "No automatic upload is required for the documented local-first workflow. Notes are stored on-device; use your own backup method." },
    { question: "Is every platform build ready to install?", answer: "No. Platform targets and published installable packages are different. Check each release asset and signing status." }
  ]} />;
}
