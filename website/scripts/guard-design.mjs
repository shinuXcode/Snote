import { readFileSync } from "node:fs";

const page = readFileSync(new URL("../app/page.tsx", import.meta.url), "utf8");
const hero = readFileSync(new URL("../components/MotionHero.tsx", import.meta.url), "utf8");
const css = readFileSync(new URL("../app/globals.css", import.meta.url), "utf8");

const required = [
  ["homepage uses the current MotionHero", /import\\s+MotionHero\\s+from/.test(page) && /<MotionHero\\s*\\/?\\s*>/.test(page)],
  ["current Snotee hero component is present", /template-hero/.test(hero)],
  ["midnight navy design tokens are present", /--bg:#07162d/.test(css) && /--accent:#3d8bff/.test(css) && /--cyan:#35e4e2/.test(css)],
  ["brand logo visibility is preserved", /\\.brand img\\{display:block/.test(css)],
];
const forbidden = [
  ["legacy blue homepage headline", /A notebook that gets out of the way\\./.test(page)],
  ["legacy feature-grid homepage", /The workspace/.test(page) && /features\\.map/.test(page)],
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
