import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Android Note-Taking App with Stylus",
  description: "Try Snotee, an open-source Android note-taking app with stylus handwriting, student notes, rich text, and PDF workflows. Check the latest APK and release notes.",
  alternates: { canonical: "https://snotee.vercel.app/android-note-taking-app" }
};

export default function AndroidNotesPage() {
  return <SearchLanding path="/android-note-taking-app" eyebrow="SNOTEE FOR ANDROID" title="Android note-taking app." accent="Built for stylus and study notes." intro="Snotee is an open-source Android note-taking app for handwritten study notes, stylus input, rich text, and PDF workflows in one local-first workspace. Compare the current APK and release notes before installing." sections={[
    { title: "Write with a stylus", body: "The project includes a custom writing surface and stylus-oriented input handling. Pressure response and palm-rejection behavior depend on the device, pen hardware, operating system, and app version.", bullets: ["Handwriting and drawing workflows", "Pressure-aware ink where supported", "Device-dependent palm rejection"] },
    { title: "Keep study material together", body: "Use notebook pages for written explanations, diagrams, and revision material. PDF-related workflows are part of the product direction; check the installed version for the exact import, annotation, and export behavior available.", bullets: ["Handwritten study notes", "Rich-text and page workflows", "PDF reading and annotation features where available"] },
    { title: "Start with the verified APK", body: "Download only from the official Snotee release page or the linked GitHub release. Review the version, release notes, and checksum when supplied. Do not install an APK from an unofficial mirror.", bullets: ["Official APK downloads", "Version history and release notes", "Open-source repository for issue reporting"] }
  ]} faqs={[
    { question: "Where can I download Snotee for Android?", answer: "Use the official download page at snotee.vercel.app/download. It reads published GitHub release assets and displays the available APK." },
    { question: "Will Snotee work with every stylus?", answer: "No universal stylus compatibility is guaranteed. Pressure, buttons, palm rejection, and latency vary by device and stylus." },
    { question: "Can I use it offline?", answer: "Snotee is documented as local-first. Keep a separate backup and check the behavior of your exact app version." }
  ]} />;
}
