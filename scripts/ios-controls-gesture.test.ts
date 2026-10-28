import { afterEach, expect, test } from 'bun:test'
import { readFileSync } from 'node:fs'
import { resolve } from 'node:path'
import { JSDOM } from 'jsdom'

const script = readFileSync(resolve(import.meta.dir, '../ios/native/src/mobile-init.js'), 'utf8')
const windows: JSDOM[] = []
afterEach(() => { for (const dom of windows.splice(0)) dom.window.close() })
function page() {
  const dom = new JSDOM('<button id="a">Message</button><button id="b">Other target</button>', {
    url: 'https://gesture-test.invalid', runScripts: 'outside-only',
  })
  windows.push(dom)
  dom.window.eval(script)
  const a = dom.window.document.getElementById('a')!, b = dom.window.document.getElementById('b')!
  const finger = (target: Element, identifier: number, touchType = 'direct') => ({ target, identifier, touchType, clientX: 10, clientY: 10 })
  const touch = (type: string, target: Element, touches: ReturnType<typeof finger>[]) => {
    const event = new dom.window.Event(type, { bubbles: true, cancelable: true })
    Object.defineProperty(event, 'touches', { value: touches })
    target.dispatchEvent(event)
    return event
  }
  const pointer = (type: string, target: Element, pointerId: number, pointerType = 'touch') => {
    const event = new dom.window.PointerEvent(type, { bubbles: true, cancelable: true, pointerId, pointerType })
    target.dispatchEvent(event)
  }
  const menu = (target = a) => {
    const event = new dom.window.MouseEvent('contextmenu', { bubbles: true, cancelable: true })
    target.dispatchEvent(event)
    return event
  }
  return { dom, a, b, finger, touch, pointer, menu }
}

test('single-finger touches, ordinary context menus and page scrolling events pass through', () => {
  const { a, finger, touch, menu } = page()
  const events: string[] = []
  for (const type of ['touchstart', 'touchmove', 'touchend', 'contextmenu']) a.addEventListener(type, () => events.push(type))
  touch('touchstart', a, [finger(a, 1)])
  expect(touch('touchmove', a, [finger(a, 1)]).defaultPrevented).toBe(false)
  menu()
  touch('touchend', a, [])
  expect(events).toEqual(['touchstart', 'touchmove', 'contextmenu', 'touchend'])
})

test('a second finger on another element cancels the first page timer before either can open a menu', async () => {
  const { dom, a, b, finger, touch, menu } = page()
  let timer = 0, menus = 0, starts = 0, cancels = 0
  for (const target of [a, b]) {
    target.addEventListener('touchstart', () => { starts++; timer = dom.window.setTimeout(() => menu(), 500) })
    target.addEventListener('touchcancel', () => { cancels++; dom.window.clearTimeout(timer) })
    target.addEventListener('contextmenu', () => { menus++ })
  }
  touch('touchstart', a, [finger(a, 1)])
  touch('touchstart', b, [finger(a, 1), finger(b, 2)])
  await new Promise(resolve => setTimeout(resolve, 550))
  expect(starts).toBe(1)
  expect(cancels).toBe(2)
  expect(menus).toBe(0)
  expect(menu().defaultPrevented).toBe(true)
})

test('pointer handlers receive cancellation and cannot treat the remainder as a new press', () => {
  const { a, b, pointer } = page()
  const events: string[] = []
  for (const target of [a, b]) for (const type of ['pointerdown', 'pointercancel', 'pointerup']) {
    target.addEventListener(type, event => events.push(`${target.id}:${type}:${(event as PointerEvent).pointerId}`))
  }
  pointer('pointerdown', a, 1)
  pointer('pointerdown', b, 2)
  pointer('pointerup', b, 2)
  pointer('pointerup', a, 1)
  expect(events).toEqual(['a:pointerdown:1', 'a:pointercancel:1', 'b:pointercancel:2'])
})

test('reserves the whole sequence and delayed context menu, then immediately allows a fresh single-finger press', () => {
  const { a, b, finger, touch, menu } = page()
  touch('touchstart', a, [finger(a, 1)])
  touch('touchstart', b, [finger(a, 1), finger(b, 2)])
  touch('touchend', b, [finger(a, 1)])
  expect(menu().defaultPrevented).toBe(true)
  touch('touchend', a, [])
  expect(menu().defaultPrevented).toBe(true)
  const click = new a.ownerDocument.defaultView!.MouseEvent('click', { bubbles: true, cancelable: true })
  a.dispatchEvent(click)
  expect(click.defaultPrevented).toBe(true)
  touch('touchstart', a, [finger(a, 3)])
  expect(menu().defaultPrevented).toBe(false)
})

test('Pencil plus one finger is left to the page and does not reserve a two-finger gesture', () => {
  const { a, b, finger, touch, menu } = page()
  touch('touchstart', a, [finger(a, 1, 'stylus'), finger(b, 2)])
  expect(menu().defaultPrevented).toBe(false)
})

test('a mouse press, keyboard input or navigation clears suppression from a completed gesture', () => {
  const { dom, a, b, finger, touch, pointer, menu } = page()
  const finishHold = () => {
    touch('touchstart', a, [finger(a, 1), finger(b, 2)])
    touch('touchend', a, [])
    expect(menu().defaultPrevented).toBe(true)
  }
  finishHold()
  pointer('pointerdown', a, 10, 'mouse')
  expect(menu().defaultPrevented).toBe(false)
  finishHold()
  a.dispatchEvent(new dom.window.KeyboardEvent('keydown', { bubbles: true, key: 'ContextMenu' }))
  expect(menu().defaultPrevented).toBe(false)
  finishHold()
  dom.window.dispatchEvent(new dom.window.Event('pagehide'))
  expect(menu().defaultPrevented).toBe(false)
})

test('backgrounding cannot leave the next foreground touch sequence reserved', () => {
  const { dom, a, b, finger, touch, menu } = page()
  touch('touchstart', a, [finger(a, 1), finger(b, 2)])
  expect(menu().defaultPrevented).toBe(true)
  Object.defineProperty(dom.window.document, 'visibilityState', { configurable: true, value: 'hidden' })
  dom.window.document.dispatchEvent(new dom.window.Event('visibilitychange'))
  touch('touchstart', a, [finger(a, 3)])
  expect(menu().defaultPrevented).toBe(false)
})
