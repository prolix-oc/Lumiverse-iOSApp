import { afterEach, expect, mock, test } from 'bun:test'
import { readFileSync } from 'node:fs'
import { JSDOM } from 'jsdom'

const html = readFileSync(new URL('../ios/tauri/ui/index.html', import.meta.url), 'utf8')
const script = readFileSync(new URL('../ios/tauri/ui/connection.js', import.meta.url), 'utf8')
const historyScript = readFileSync(new URL('../ios/tauri/ui/connection-history.js', import.meta.url), 'utf8')
const windows: JSDOM[] = []

afterEach(() => {
  for (const dom of windows.splice(0)) dom.window.close()
})

function deferred<T>() {
  let resolve!: (value: T) => void
  let reject!: (error: Error) => void
  const promise = new Promise<T>((yes, no) => { resolve = yes; reject = no })
  return { promise, resolve, reject }
}

function connectionPage(query = '') {
  const saved = deferred<{ server: string | null; allowInsecureHttp?: boolean; history?: { server: string; allowInsecureHttp?: boolean }[] }>()
  const connected = deferred<void>()
  const invoke = mock((command: string) => command === 'mobile_connection_info' ? saved.promise : connected.promise)
  const dom = new JSDOM(html, { url: `https://tauri.localhost/index.html${query}`, runScripts: 'outside-only' })
  windows.push(dom)
  Object.assign(dom.window, { __TAURI_INTERNALS__: { invoke } })
  dom.window.eval(`(() => {\n${historyScript}\n${script}\n})()`)
  const element = <T extends HTMLElement>(id: string) => dom.window.document.getElementById(id) as T
  return {
    dom, saved, connected, invoke,
    setup: element('connection-setup'),
    visibleContent: () => [...dom.window.document.querySelectorAll('main img, main h1, main p, main form')]
      .filter(element => !element.closest('[hidden]')),
    server: element<HTMLInputElement>('server'),
    button: element<HTMLButtonElement>('connect'),
    status: element('status'),
    httpSettings: element('http-settings'),
    allowInsecureHttp: element<HTMLInputElement>('allow-insecure-http'),
  }
}

async function flush() { await Promise.resolve(); await Promise.resolve() }

test('startup stays visually empty while restoring and reconnecting a saved server', async () => {
  const page = connectionPage()
  expect(page.setup.hidden).toBe(true)
  expect(page.visibleContent()).toHaveLength(0)

  page.saved.resolve({ server: 'https://my-server.example/' })
  await flush()

  expect(page.invoke).toHaveBeenCalledWith('mobile_connect', { server: 'https://my-server.example/', restore: true, allowInsecureHttp: false })
  expect(page.setup.hidden).toBe(true)
  expect(page.visibleContent()).toHaveLength(0)
  expect(page.server.disabled).toBe(true)
  page.connected.resolve()
  await flush()
  expect(page.setup.hidden).toBe(true)
  expect(page.visibleContent()).toHaveLength(0)
})

test('first launch reveals setup after determining that no server is configured', async () => {
  const page = connectionPage()
  page.saved.resolve({ server: null })
  await flush()

  expect(page.setup.hidden).toBe(false)
  expect(page.server.disabled).toBe(false)
  expect(page.invoke).toHaveBeenCalledTimes(1)
})

test('Change server reveals the saved address without reconnecting', async () => {
  const page = connectionPage('?changeServer=1')
  page.saved.resolve({ server: 'https://my-server.example/' })
  await flush()

  expect(page.server.value).toBe('https://my-server.example/')
  expect(page.setup.hidden).toBe(false)
  expect(page.invoke).toHaveBeenCalledTimes(1)
})

test('a failed reconnect reveals the saved address and a usable retry form', async () => {
  const page = connectionPage()
  page.saved.resolve({ server: 'https://my-server.example/' })
  await flush()
  page.connected.reject(new Error('Server unavailable'))
  await flush()

  expect(page.setup.hidden).toBe(false)
  expect(page.status.textContent).toBe('Server unavailable')
  expect(page.server.value).toBe('https://my-server.example/')
  expect(page.server.disabled).toBe(false)
  expect(page.button.disabled).toBe(false)
})

test('failure reading saved settings reveals setup with an explanation', async () => {
  const page = connectionPage()
  page.saved.reject(new Error('Settings unavailable'))
  await flush()

  expect(page.setup.hidden).toBe(false)
  expect(page.status.textContent).toContain('Could not restore the saved server address')
})

function enterServer(page: ReturnType<typeof connectionPage>, address: string) {
  page.server.value = address
  page.server.dispatchEvent(new page.dom.window.Event('input', { bubbles: true }))
}

function submit(page: ReturnType<typeof connectionPage>) {
  page.dom.window.document.getElementById('connection-form')!.dispatchEvent(new page.dom.window.Event('submit', { bubbles: true, cancelable: true }))
}

test('HTTP cannot invoke a connection until the user explicitly opts in', async () => {
  const page = connectionPage()
  page.saved.resolve({ server: null })
  await flush()
  enterServer(page, 'http://192.168.1.2:8000')
  expect(page.httpSettings.hidden).toBe(false)
  submit(page)
  expect(page.invoke).toHaveBeenCalledTimes(1)
  expect(page.status.textContent).toContain('enable Allow insecure HTTP')
  expect(page.button.disabled).toBe(false)
  page.allowInsecureHttp.checked = true
  submit(page)
  expect(page.invoke).toHaveBeenCalledWith('mobile_connect', { server: 'http://192.168.1.2:8000', restore: false, allowInsecureHttp: true })
})

test('changing an address clears its HTTP consent, including changing only the port', async () => {
  const page = connectionPage('?changeServer=1')
  page.saved.resolve({ server: 'http://server.local:8000/', allowInsecureHttp: true })
  await flush()
  expect(page.allowInsecureHttp.checked).toBe(true)
  enterServer(page, 'http://server.local:8001/')
  expect(page.allowInsecureHttp.checked).toBe(false)
  submit(page)
  expect(page.invoke).toHaveBeenCalledTimes(1)
  enterServer(page, 'https://server.example/')
  expect(page.httpSettings.hidden).toBe(true)
  submit(page)
  expect(page.invoke).toHaveBeenCalledWith('mobile_connect', { server: 'https://server.example/', restore: false, allowInsecureHttp: false })
})

test('an approved HTTP server restores its permission across launches', async () => {
  const page = connectionPage()
  page.saved.resolve({ server: 'http://server.local:8000/', allowInsecureHttp: true })
  await flush()
  expect(page.setup.hidden).toBe(true)
  expect(page.invoke).toHaveBeenCalledWith('mobile_connect', { server: 'http://server.local:8000/', restore: true, allowInsecureHttp: true })
})

test('an old HTTP setting without consent stays on setup without connecting', async () => {
  const page = connectionPage()
  page.saved.resolve({ server: 'http://server.local:8000/' })
  await flush()
  expect(page.setup.hidden).toBe(false)
  expect(page.allowInsecureHttp.checked).toBe(false)
  expect(page.invoke).toHaveBeenCalledTimes(1)
})

test('history stays collapsed and selecting a previous server fills the form without connecting', async () => {
  const page = connectionPage('?changeServer=1')
  page.saved.resolve({ server: 'https://current.example/', history: [
    { server: 'https://current.example/' }, { server: 'https://previous.example:8443/' },
  ] })
  await flush()
  const details = page.dom.window.document.querySelector('details')!
  expect(details.open).toBe(false)
  expect(page.dom.window.document.getElementById('history-count')!.textContent).toBe(' (2)')
  details.open = true
  const choices = page.dom.window.document.querySelectorAll<HTMLButtonElement>('.history-server')
  expect(choices[1]!.textContent).toContain('previous.example:8443')
  choices[1]!.click()
  expect(page.server.value).toBe('https://previous.example:8443/')
  expect(page.invoke).toHaveBeenCalledTimes(1)
  submit(page)
  expect(choices[0]!.disabled).toBe(true)
  expect(page.invoke).toHaveBeenLastCalledWith('mobile_connect', { server: 'https://previous.example:8443/', restore: false, allowInsecureHttp: false })
  page.connected.reject(new Error('Offline'))
  await flush()
  expect(choices[0]!.disabled).toBe(false)
  expect(page.dom.window.document.querySelectorAll('.history-server')).toHaveLength(2)
})

test('history shortcut expands the list and restores HTTP consent only for the selected saved origin', async () => {
  const page = connectionPage('?changeServer=1&history=1')
  page.saved.resolve({ server: 'https://current.example/', history: [{ server: 'http://lan.local:8000/', allowInsecureHttp: true }] })
  await flush()
  expect(page.dom.window.document.querySelector('details')!.open).toBe(true)
  page.dom.window.document.querySelector<HTMLButtonElement>('.history-server')!.click()
  expect(page.httpSettings.hidden).toBe(false)
  expect(page.allowInsecureHttp.checked).toBe(true)
  enterServer(page, 'http://lan.local:8001/')
  expect(page.allowInsecureHttp.checked).toBe(false)
})

test('removing history persists natively, does not connect, and preserves the entered address', async () => {
  const page = connectionPage('?changeServer=1&history=1')
  page.saved.resolve({ server: 'https://current.example/', history: [{ server: 'https://old.example/' }] })
  await flush()
  page.invoke.mockImplementation(async () => ({ history: [] }) as any)
  page.dom.window.document.querySelector<HTMLButtonElement>('.history-remove')!.click()
  submit(page)
  expect(page.invoke).toHaveBeenLastCalledWith('mobile_forget_connection', { server: 'https://old.example/' })
  await flush()
  expect(page.server.value).toBe('https://current.example/')
  expect(page.dom.window.document.querySelectorAll('.history-server')).toHaveLength(0)
  expect(page.dom.window.document.getElementById('history-empty')!.hidden).toBe(false)
  expect(page.status.textContent).toBe('Server removed from history.')
})

test('a failed removal keeps the history available for retry', async () => {
  const page = connectionPage('?changeServer=1&history=1')
  page.saved.resolve({ server: 'https://current.example/', history: [{ server: 'https://old.example/' }] })
  await flush()
  page.invoke.mockImplementation(async () => { throw new Error('Storage unavailable') })
  const remove = page.dom.window.document.querySelector<HTMLButtonElement>('.history-remove')!
  remove.click()
  await flush()
  expect(page.dom.window.document.querySelectorAll('.history-server')).toHaveLength(1)
  expect(remove.disabled).toBe(false)
  expect(page.status.textContent).toContain('Could not remove this server')
})
