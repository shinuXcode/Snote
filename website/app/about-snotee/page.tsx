import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "Snotee: Open-Source Local-First Notes",
  description: "Learn what Snotee is, who builds it, how local-first storage works, which platforms have published builds, and where to find its source code.",
  alternates: { canonical: "https://snotee.vercel.app/about-snotee" }
};

export default function AboutSnoteePage() {
  return <SearchLanding path="/about-snotee" eyebrow="ABOUT SNOTEE" title="A note-taking workspace" accent="built in the open." intro="Snotee is an independent, open-source note-taking project created by Sadab. It brings handwriting, stylus-oriented writing, rich text, and document workflows into a local-first workspace, with platform availability determined by published releases." sections={[
    { title: "An independent open-source project", body: "Snotee is developed in public. Its repository contains the Flutter application, website, documentation, and release automation. The project is licensed under MIT; read the repository license and third-party notices before redistribution.", bullets: ["Creator: Sadab", "Source: github.com/shinuXcode/Snote", "License: MIT"] },
    { title: "Local-first by design", body: "The project documentation describes on-device storage using SQLite and local files. Core note-taking is designed not to require a Snotee-hosted account, database, or always-on server. Backups and transfers should remain under the user's control.", bullets: ["No mandatory Snotee account described in the project README", "No automatic cross-device sync required", "Keep independent backups and verify restore before deleting originals"] },
    { title: "Platforms and release transparency", body: "The project targets Android, iOS, Windows, macOS, Linux, and Web. A target platform is not the same as a ready-to-install package: check the current release page for an actual artifact, signing status, and platform-specific instructions.", bullets: ["Android APK and desktop archives when attached to a release", "iOS installation requires an Apple-signed build", "Web build availability is listed separately"] }
  ]} faqs={[
    { question: "Is Snotee free and open source?", answer: "The repository is public and its README identifies the project as MIT-licensed. Check the current LICENSE file and third-party notices for exact terms." },
    { question: "Does Snotee upload my notes?", answer: "The project is documented as local-first and does not require a Snotee-hosted server for core note-taking. Review the exact installed build and its settings before relying on any privacy assumption." },
    { question: "Does Snotee have AI note generation?", answer: "Do not assume AI note generation or summarization is included. Check the current release notes and feature documentation; this website does not advertise an unverified AI feature." }
  ]} />;
}
