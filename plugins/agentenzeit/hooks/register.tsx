import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Stand } from '../types'

// Liest den Zustand, den das Plugin «agentenzeit» je Sitzung schreibt
// (~/.claude/plugins/data/agentenzeit-letsautomate/sitzungen/<id>.json).
// Gemessen und gemeldet wird nur dort; die Leiste zeigt und schaltet.
const stand = atom({ plugin: 'agentenzeit', key: 'stand' } as const, null)
const zu = atom({ plugin: 'agentenzeit', key: 'zu' } as const, false)

async function laden($: EngineInterface): Promise<Stand | null> {
  const home = await $.env.get('HOME')
  const id = await $.session.id()
  if (!home || !id) return null
  try {
    const z = JSON.parse(await $.fs.read(`${home}/.claude/plugins/data/agentenzeit-letsautomate/sitzungen/${id}.json`))
    const a = typeof z.aufgabe === 'string' && z.aufgabe !== '' ? z.aufgabe : null
    return {
      aufgabe: a === 'KEINE' ? null : a,
      aus: a === 'KEINE',
      offenMin: Math.round((Number(z.offen) || 0) / 60),
      gemeldetMin: Math.round((Number(z.gemeldet_total) || 0) / 60),
    }
  } catch {
    return { aufgabe: null, aus: false, offenMin: 0, gemeldetMin: 0 }
  }
}

function zeile(s: Stand): string {
  const was = s.aus ? 'aus' : s.aufgabe ?? 'keine Aufgabe'
  return `⏱ Agentenzeit: ${was} · ${s.offenMin} min offen · ${s.gemeldetMin} min gemeldet`
}

async function auffrischen($: EngineInterface) {
  const s = await laden($)
  await update($, stand, () => s)
  $.ui.status(s ? zeile(s) : undefined)
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    const r = await next(e)
    await auffrischen($)
    $.clock.every(60_000, () => auffrischen($))
    return r
  })

  // Der Zustand ändert sich, wenn das Plugin bei einer Eingabe misst oder
  // eine Meldung verbucht: nach jedem Zug neu lesen.
  on('turn.complete', async ($, e, next) => {
    const r = await next(e)
    await auffrischen($)
    return r
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const s = await read($, stand)
    if (e.props.hasSurvey || s === null || (await read($, zu))) {
      return next(e)
    }
    const { Box, Button, Text } = $.ui.resolve(e)

    return (
      <Box>
        <Text dimColor>{zeile(s)} </Text>
        <Button key="setzen" label={s.aufgabe ? 'Aufgabe wechseln' : 'Aufgabe setzen'}
          onPress={() => $.prompt.fill({ text: '/aufgabe ', mode: 'replace' })} />
        {s.aus ? null : (
          <Button key="aus" label="Aus" onPress={() => $.command.run({ command: 'aufgabe keine' })} />
        )}
        <Button key="zu" label="–" onPress={() => update($, zu, () => true)} />
      </Box>
    )
  })
}
