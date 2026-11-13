// 1. Two concurrent loadComputed() calls start dynamic imports (the
//    real-world situation being a CMS like VitePress 2.0.0-alpha.21
//    dispatching renders)
// 2. (The AI thinks that) when the first loadComputed() settles, its
//    page module is sync-required while the second page's async
//    import prepare is still holding the module graph update permit.
//    That prepare is a task on the main runtime, which is blocked
//    inside the sync require -> deadlock.

import { createRequire } from 'node:module'

const here = import.meta.dirname

async function loadComputed (stem) {
  console.log(`import(${stem}.js) starting...`);
  await import(`${here}/${stem}.js`)
  console.log(`import(${stem}.js) settled`);
}

const r1 = loadComputed('p1')
const r2 = loadComputed('p2')

await r1
console.log('Starting createRequire (p2 import still in flight)...')
createRequire(here)(`${here}/p1.js`)
console.log('createRequire done')

await r2
console.log('ALL DONE')
