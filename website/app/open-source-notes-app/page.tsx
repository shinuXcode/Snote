import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Open-Source Notes App for Android & Desktop",
  description: "Explore Snotee's open-source Flutter code, MIT license, local-first storage, handwriting, and PDF workflows for Android and desktop.",
  alternates: { canonical: "https://snotee.vercel.app/open-source-notes-app" }
};

export default function OpenSourceNotesPage() {
  return <SearchLanding path="/open-source-notes-app" eyebrow="OPEN-SOURCE NOTES" title="Open code." accent="Your notes stay yours." intro="Snotee is a public, MIT-licensed note-taking project. Its repository includes the Flutter app, website, documentation, and release workflows, with a local-first approach to note storage." sections={[
    { title: "Inspect the implementation", body: "The source repository is available on GitHub. Developers can inspect the application structure, follow changes, review issues, and contribute focused improvements.", bullets: ["Public repository: shinuXcode/Snote", "MIT license in the repository", "Flutter and Dart application code"] },
    { title: "Local-first storage model", body: "The project README describes SQLite metadata and local filesystem storage for note data. Core note-taking is intended to work without a Snotee-hosted database or mandatory cloud account.", bullets: ["On-device data storage", "No required hosted Snotee server for core notes", "User-controlled backup and transfer approach"] },
    { title: "Contribute responsibly", body: "Open-source development works best with reproducible reports, focused pull requests, tests, and careful handling of user data. Never attach private notebooks, access tokens, or credentials to public issues.", bullets: ["Read contribution and build instructions", "Report version, device, and reproduction steps", "Keep secrets and personal note content out of commits"] }
  ]} faqs={[
    { question: "What license does Snotee use?", answer: "The repository README identifies Snotee as MIT-licensed. Read the LICENSE file and bundled third-party notices for the exact legal terms." },
    { question: "Can I self-host Snotee?", answer: "The core application is documented as local-first and does not require a Snotee server. Web hosting and optional integrations have separate setup requirements." },
    { question: "Where can I report bugs or contribute?", answer: "Use the official GitHub repository's issue and pull request workflows. Remove secrets and personal note content from reports." }
  ]} />;
}
