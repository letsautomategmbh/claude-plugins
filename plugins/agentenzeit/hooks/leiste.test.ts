import { expect, test } from 'claude-code/testing'
import type { On } from 'claude-code'

// Steht für die Zustandsdatei, die das Plugin «agentenzeit» je Sitzung schreibt.
function zustand(on: On, z: Record<string, unknown>, gelesen: string[] = []) {
  on('env.get', async (_$, e) => ({ value: e.name === 'HOME' ? '/Users/test' : undefined }))
  on('session.id', async () => ({ value: 's1' }))
  on('session.start', async (_$, e) => ({ cwd: e.cwd }))
  on('clock.every', async () => ({ value: undefined }) as never)
  on('ui.status', async () => ({ value: undefined }) as never)
  on('ui.render', async () => ({ type: 'Box', props: {}, children: [] }) as never)
  on('fs.read', async (_$, e) => {
    gelesen.push(e.path)
    return { value: JSON.stringify(z) }
  })
}

for (const surface of ['terminal', 'desktop'] as const) {
  test(`${surface}: Leiste zeigt den Stand, «Aus» schaltet das Melden ab`, async ($, on) => {
    const gelesen: string[] = []
    const gesendet: string[] = []
    zustand(on, { aufgabe: 'A123', offen: 720, gemeldet_total: 1800 }, gelesen)
    on('command.run', async (_$, e) => {
      gesendet.push(e.command)
      return { text: '' } as never
    })
    await $.session.start({ cwd: '/tmp', surface, isInteractive: true })
    expect(gelesen).toEqual(['/Users/test/.claude/plugins/data/agentenzeit-letsautomate/sitzungen/s1.json'])

    const ui = await $.ui.mount({ plugin: 'agentenzeit', surface, component: 'AbovePrompt', props: { hasSurvey: false } as never })
    expect(JSON.stringify(await ui.drawn())).toContain('A123 · 12 min offen · 30 min gemeldet')

    await ui.press({ key: 'aus' })
    expect(gesendet).toEqual(['aufgabe keine'])
  })
}

test('ausgeschaltet: «aus» und kein Knopf zum Ausschalten', async ($, on) => {
  zustand(on, { aufgabe: 'KEINE', offen: 0 })
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'agentenzeit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false } as never })
  expect(JSON.stringify(await ui.drawn())).toContain('Agentenzeit: aus')
  expect(await ui.find({ key: 'aus' })).toBeUndefined()
})

test('«–» blendet aus, /agentenzeit holt die Leiste zurück', async ($, on) => {
  zustand(on, { aufgabe: 'A7', offen: 60 })
  on('prompt.submit', async (_$, e) => ({ text: e.text }) as never)
  await $.session.start({ cwd: '/tmp', surface: 'terminal', isInteractive: true })
  const ui = await $.ui.mount({ plugin: 'agentenzeit', surface: 'terminal', component: 'AbovePrompt', props: { hasSurvey: false } as never })
  await ui.press({ key: 'zu' })
  expect(await ui.find({ key: 'aus' })).toBeUndefined()
  await $.prompt.submit({ text: '/agentenzeit' } as never)
  expect(await ui.find({ key: 'aus' })).toBeDefined()
})

