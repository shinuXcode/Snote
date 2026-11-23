import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";
export const metadata: Metadata = { title: "Snotee — Open-Source Handwriting Notes App", description: "Snotee is a free, open-source note-taking app for handwriting, stylus notes, PDF annotation, and student study notes. Local-first and available across Android and desktop releases.", alternates: { canonical: "https://snotee.vercel.app/" }, openGraph: { title: "Snotee — Notes for Creators", description: "Open-source, local-first note-taking for handwriting and ideas.", url: "https://snotee.vercel.app/", type: "website" } };
export default function Home() { return <MotionHero />; }
