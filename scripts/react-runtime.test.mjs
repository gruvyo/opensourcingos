import assert from 'node:assert/strict'
import { test } from 'node:test'
import { createElement, useState, version as reactVersion } from 'react'
import { version as reactDomVersion } from 'react-dom'
import { renderToString } from 'react-dom/server'

test('installed React and React DOM agree and can render a component with hooks', () => {
  assert.equal(reactVersion, reactDomVersion)

  function Status() {
    const [message] = useState('Ready')
    return createElement('output', null, message)
  }

  assert.equal(renderToString(createElement(Status)), '<output>Ready</output>')
})
