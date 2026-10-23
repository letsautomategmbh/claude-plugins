export type Stand = {
  aufgabe: string | null
  aus: boolean
  offenMin: number
  gemeldetMin: number
}

declare module 'claude-code' {
  interface PluginState {
    'agentenzeit': { stand: Stand | null }
  }
}
