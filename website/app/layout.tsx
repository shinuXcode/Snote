import type {Metadata} from "next";
import "./globals.css";
import Link from "next/link";
import MobileNav from "../components/MobileNav";

export const metadata:Metadata={
  title:"Snote — Write without limits",
  description:"Open-source, offline-first handwriting and rich-text notes."
};

const nav=[
  ["/features","Features"],
  ["/how-it-works","How it works"],
  ["/download","Download"],
  ["/founder","Founder"],
  ["/account","Account"],
];

export default function RootLayout({children}:{children:React.ReactNode}){
  return <>
    <header className="nav">
      <div className="shell navin">
        <Link href="/" className="brand">
          <img src="/snote-logo.svg" alt="Snote" />
          <span>Snote</span>
        </Link>
        <nav className="links">
          {nav.map(([href,label])=><Link key={href} href={href}>{label}</Link>)}
        </nav>
        <MobileNav />
      </div>
    </header>
    {children}
    <footer className="footer">
      <div className="shell footerin">
        <span>Snote · Open source · Offline first</span>
        <span>Android · iOS · Windows · macOS · Linux · Web</span>
      </div>
    </footer>
  </>;
}
