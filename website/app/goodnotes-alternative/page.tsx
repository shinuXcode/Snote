import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Goodnotes Alternative for Android? Compare Snotee",
  description: "Compare Snotee with Goodnotes for Android handwriting, local-first notes, PDF workflows, platform support, and limitations.",
  alternates: { canonical: "https://snotee.vercel.app/goodnotes-alternative" }
};

export default function GoodnotesAlternativePage() {
  return <SearchLanding path="/goodnotes-alternative" eyebrow="APP COMPARISON" title="Looking for a Goodnotes alternative" accent="on Android?" intro="Snotee is an open-source note-taking project worth evaluating if you prefer public source code and a local-first approach. It is not a claim of feature parity with Goodnotes: compare the exact tools, PDF behavior, device support, and export needs before switching." sections={[
    { title: "Different product priorities", body: "Snotee emphasizes open development, local-first note storage, handwriting, and document workflows. Goodnotes is a separate commercial product with its own feature set, integrations, and platform policies.", bullets: ["Snotee: public source repository and MIT license", "Snotee: local-first architecture described in project documentation", "Goodnotes: consult its official current feature and pricing pages"] },
    { title: "Check your must-have features", body: "A serious comparison should test the actual work you do rather than rely on a feature checklist. Try handwriting latency, pen pressure, PDF import, annotation persistence, search, backup, and export on your own device.", bullets: ["Test your stylus and tablet", "Open representative PDFs", "Verify backup and restore before migrating"] },
    { title: "Try Snotee without guessing", body: "Download the latest published build from the official release page, read its notes, and keep your existing notes untouched until you have tested the workflow end to end.", bullets: ["Check Android APK availability", "Review desktop and iOS signing status", "Compare the current release rather than old screenshots"] }
  ]} faqs={[
    { question: "Is Snotee a full Goodnotes replacement?", answer: "No feature-parity claim is made. Snotee is an independent open-source project; compare the current features and test your own workflow before switching." },
    { question: "Is Snotee available for Android?", answer: "The project targets Android and published releases may include an APK. Check the official download page for the current asset." },
    { question: "Is Snotee free?", answer: "The project is public and MIT-licensed according to its README. Check the current repository license and release notes." }
  ]} />;
}
