import type { Metadata } from "next";
import SearchLanding from "../../components/SearchLanding";

export const metadata: Metadata = {
  title: "PDF Annotation for Study and Reading",
  description: "Explore Snotee's PDF reading and annotation workflows alongside handwritten notes. Check release-specific platform support before downloading.",
  alternates: { canonical: "https://snotee.vercel.app/pdf-annotation" }
};

export default function PdfAnnotationPage() {
  return <SearchLanding path="/pdf-annotation" eyebrow="PDF READING & ANNOTATION" title="Read closely." accent="Annotate with context." intro="Snotee brings document workflows into an open-source note-taking project focused on handwriting and study. PDF capabilities can vary by platform and release, so review the current build notes before depending on a specific annotation workflow." sections={[
    { title: "A workspace for reading", body: "A useful PDF workflow needs more than a file viewer: readable pages, predictable navigation, zoom, and a place to capture explanations. Snotee's product direction brings document work alongside notebook pages.", bullets: ["PDF reading workflows", "Study notes alongside reference material", "Platform-specific behavior documented by release"] },
    { title: "Understand annotation and export behavior", body: "Before annotating important documents, test how your installed version stores annotations, whether the source PDF remains unchanged, and what is included when you export or back up a notebook.", bullets: ["Keep an original copy of important PDFs", "Verify annotation persistence after closing and reopening", "Test export and restore before relying on it"] },
    { title: "Choose a build that exists", body: "The official download page lists actual published release assets. A platform target does not guarantee every PDF feature is available on every operating system.", bullets: ["Check release version and notes", "Use official download links", "Report reproducible issues with sanitized examples"] }
  ]} faqs={[
    { question: "Is Snotee a dedicated PDF reader?", answer: "Snotee is a broader note-taking workspace that includes PDF-related workflows. Check the current release for exact reader and annotation capabilities." },
    { question: "Can I annotate every PDF?", answer: "Compatibility can vary with PDF structure, file size, embedded fonts, and the platform build. Test complex documents before depending on them." },
    { question: "Will annotations be embedded into the original PDF?", answer: "Do not assume this. Verify the export behavior in your installed version and preserve the original file." }
  ]} />;
}
