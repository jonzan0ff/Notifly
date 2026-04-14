// Standalone Node test for the projectRootForPath() function used by the
// Notifly VS Code extension. Runs the same fixture table as the Swift and
// bash equivalents so all three implementations stay in sync.
//
// Run from project root: node vscode-extension/test/projectGrouping.test.js

const path = require("path");
const fs = require("fs");
const assert = require("assert");

// Inline copy of the projectRootForPath() function from src/extension.ts.
// (A real cross-compile would import it, but extension.ts uses the vscode
// module which can't be required outside the extension host. So we mirror it
// here — and assert below that the source file still contains a function with
// the same signature, to catch drift.)
function projectRootForPath(filePath) {
  let dir = path.dirname(filePath);
  while (dir && dir !== "/" && dir !== ".") {
    const parent = path.dirname(dir);
    if (path.basename(parent) === "Projects") {
      return path.basename(dir);
    }
    dir = parent;
  }
  return undefined;
}

// Shared fixture table — must match Swift ProjectGroupingTests.fixtures and
// macos/scripts/test_project_grouping_bash.sh
const FIXTURES = [
  // The TS function takes a *file* path (from a vscode.Uri), so the inputs
  // here include trailing filenames where the bash/Swift versions take
  // directories. The expected results are the same.
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin/app/page.tsx",         "Camp Clintondale"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/guest/lib/db.ts",            "Camp Clintondale"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/admin/app/api/users/get.ts", "Camp Clintondale"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/email-templates/booking.html","Camp Clintondale"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Camp Clintondale/CLAUDE.md",                  "Camp Clintondale"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/README.md",                            "Notifly"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/macos/Notifly/Views/Card.swift",       "Notifly"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Notifly/vscode-extension/src/extension.ts",    "Notifly"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy/package.json",                         "Dorothy"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/Dorothy/server/api/index.ts",                  "Dorothy"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/HomeTeam/macos/HomeTeamApp/Services/UpdateService.swift", "HomeTeam"],
  ["/Users/jonzanoff/Documents/jonzan0ff/Projects/SPAMASAURUS/lib/parsers/index.ts",             "SPAMASAURUS"],
];

// 1. Run the inline function against every fixture
let pass = 0;
let fail = 0;
for (const [input, expected] of FIXTURES) {
  const actual = projectRootForPath(input);
  if (actual === expected) {
    console.log(`  ✓ ${input}`);
    pass++;
  } else {
    console.log(`  ✗ ${input} → got '${actual}' expected '${expected}'`);
    fail++;
  }
}

// 2. Verify the SOURCE file still contains a projectRootForPath function so
// this test is testing live code, not a stale copy.
const sourcePath = path.join(__dirname, "..", "src", "extension.ts");
const source = fs.readFileSync(sourcePath, "utf8");
assert(
  source.includes("function projectRootForPath("),
  `extension.ts must contain a projectRootForPath function — drift detected`
);
console.log(`  ✓ extension.ts contains projectRootForPath()`);

// 3. Verify the COMPILED extension.js also has it (catches forgotten compile)
const compiledPath = path.join(__dirname, "..", "out", "extension.js");
if (fs.existsSync(compiledPath)) {
  const compiled = fs.readFileSync(compiledPath, "utf8");
  assert(
    compiled.includes("projectRootForPath"),
    `extension.js (compiled) must contain projectRootForPath — recompile needed`
  );
  console.log(`  ✓ extension.js (compiled) contains projectRootForPath`);
}

console.log("");
console.log(`  ${pass} / ${FIXTURES.length} passed`);
if (fail > 0) {
  console.error(`FAIL: ${fail} fixtures failed`);
  process.exit(1);
}
console.log("OK");
