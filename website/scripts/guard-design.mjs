import { readFileSync } from "node:fs";

const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const hero = readFileSync(new URL("../components/MotionHero.tsx", import.meta.url), "utf8");
const css = readFileSync(new URL("../app/brand-overrides.css", import.meta.url), "utf8");

const required = [
  ["homepage uses the current MotionHero", /import\s+MotionHero\s+from/.test(page) && /<MotionHero\s*\/?\s*>/.test(page)],
  ["current Snotee hero component is present", /template-hero/.test(hero)],
  ["espresso brown design tokens are present", /--bg:\s*#160f0b/.test(css) && /--accent:\s*#c58b57/.test(css) && /--cyan:\s*#e2b77e/.test(css)],
  ["brand logo visibility is preserved", /\.brand img/.test(css)],
];
const forbidden = [
  ["legacy blue homepage headline", /A notebook that gets out of the way\./.test(page)],
];
let failed = false;
for (const [label, ok] of required) {
  console.log((ok ? "PASS " : "FAIL ") + label);
  if (!ok) failed = true;
}
for (const [label, found] of forbidden) {
  console.log((found ? "FAIL " : "PASS ") + label);
  if (found) failed = true;
}
if (failed) {
  console.error("Build blocked: restore the approved Snotee website design before deploying.");
  process.exit(1);
}
