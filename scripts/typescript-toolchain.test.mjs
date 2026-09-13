import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { test } from 'node:test'
import ts from 'typescript'

const projectRoot = fileURLToPath(new URL('../', import.meta.url))
const nativeCompiler = path.join(projectRoot, 'node_modules/@typescript/native/bin/tsc')

test('native type checking and the compiler API both detect invalid assignments', () => {
  const directory = mkdtempSync(path.join(tmpdir(), 'opensourcingos-typescript-'))
  try {
    const source = path.join(directory, 'sample.ts')
    const config = path.join(directory, 'tsconfig.json')
    const compilerOptions = {
      strict: true, noEmit: true, types: [], lib: ['ES2020'],
      module: 'NodeNext', moduleResolution: 'NodeNext',
    }
    writeFileSync(config, JSON.stringify({ compilerOptions, files: ['sample.ts'] }))
    const options = ts.convertCompilerOptionsFromJson(compilerOptions, directory)
    assert.deepEqual(options.errors, [])

    for (const [value, expectedCode] of [['42', undefined], ['"invalid"', 2322]]) {
      writeFileSync(source, `export const total: number = ${value};\n`)
      const program = ts.createProgram([source], options.options)
      const diagnostics = ts.getPreEmitDiagnostics(program)
      assert.deepEqual(diagnostics.map(diagnostic => diagnostic.code), expectedCode ? [expectedCode] : [])

      const result = spawnSync(process.execPath, [nativeCompiler, '--project', config, '--pretty', 'false'], {
        cwd: projectRoot, encoding: 'utf8', timeout: 30_000,
      })
      assert.ifError(result.error)
      assert.equal(result.signal, null)
      const output = result.stdout + result.stderr
      if (expectedCode) {
        assert.notEqual(result.status, 0, output)
        assert.match(output, /error TS2322:/)
      } else {
        assert.equal(result.status, 0, output)
      }
    }
  } finally {
    rmSync(directory, { recursive: true, force: true })
  }
})
