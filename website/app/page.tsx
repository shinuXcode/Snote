import type { Metadata } from "next";
import MotionHero from "../components/MotionHero";
export const metadata: Metadata = { title: "Snotee — Open-Source Handwriting Notes App", description: "Snotee is a free, open-source notes app for handwriting, stylus input, PDF annotation, and student study notes. Local-first on Android and desktop.", alternates: { canonical: "https://snotee.vercel.app/" }, openGraph: { title: "Snotee — Notes for Creators", description: "Open-source, local-first note-taking for handwriting and ideas.", url: "https://snotee.vercel.app/", type: "website" } };
export default function Home() { return <MotionHero />; }
