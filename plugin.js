/**
 * hermes-desktop-statusbar — CLI-style status bar for the Hermes desktop app.
 *
 * Renders, in the desktop status bar:
 *
 *   deepseek-v4.1-flash │ [████░░░░░░] 42% │ 12.3k/200k │ ◎ 87% │ ↑42 t/s │ ↑1.2k ↓340
 *   ＋ 新對話 (New)   ■ 停止 (Stop)   ☰ 會話 (Sessions)
 *
 * Data sources
 *   - host.state.focusedUsage  — live-streamed UsageStats (updates mid-turn)
 *   - session.usage RPC        — polled every 5s, so the context % is populated
 *                                the moment a session opens (focusedUsage is
 *                                empty until the first turn finishes)
 *
 * Actions
 *   ＋  navigate to the new-chat route
 *   ■  session.interrupt on the focused session (disabled when idle)
 *   ☰  recent sessions from session.list; click to jump
 *
 * Install: copy this folder to <HERMES_HOME>/desktop-plugins/hermes-desktop-statusbar/
 * then run "Reload desktop plugins" from the command palette (Ctrl/Cmd+K).
 *
 * Only @hermes/plugin-sdk, react and react/jsx-runtime resolve here — the file
 * is loaded uncompiled, so UI is built with jsx() calls, not JSX syntax.
 */

import { haptic, host, STATUSBAR_AREAS, useValue } from '@hermes/plugin-sdk'
import { jsx, jsxs } from 'react/jsx-runtime'
import { useEffect, useState } from 'react'

const ID = 'hermes-desktop-statusbar'

function num(v) {
  return typeof v === 'number' && Number.isFinite(v) ? v : null
}

/** 12345 → 12.3k, 1234567 → 1.2M */
function kfmt(n) {
  const v = num(n) || 0
  if (v >= 1000000) return (v / 1000000).toFixed(1) + 'M'
  if (v >= 1000) return (v / 1000).toFixed(1) + 'k'
  return String(Math.round(v))
}

/** ██████░░░░ — same visual language as the CLI status bar. */
function contextBar(percent, width = 10) {
  const b = Math.max(0, Math.min(100, percent ?? 0))
  const filled = Math.round((b / 100) * width)
  return '█'.repeat(filled) + '░'.repeat(width - filled)
}

/** Live usage wins; the RPC snapshot fills whatever the stream hasn't reported yet. */
function merge(live, snapshot) {
  if (!live) return snapshot || {}
  if (!snapshot) return live
  const out = { ...snapshot, ...live }
  const keys = [
    'context_used',
    'context_max',
    'context_percent',
    'cache_hit_pct',
    'avg_tps',
    'input',
    'output',
    'total',
    'cost_usd'
  ]
  for (const k of keys) {
    if (num(out[k]) == null && num(snapshot[k]) != null) out[k] = snapshot[k]
  }
  return out
}

const chipBtn = {
  display: 'inline-flex',
  alignItems: 'center',
  height: '100%',
  padding: '0 6px',
  fontSize: '0.6875rem',
  lineHeight: 1,
  color: 'var(--ui-text-secondary)',
  background: 'transparent',
  border: 'none',
  cursor: 'pointer'
}

function SessionsList({ onClose }) {
  const [rows, setRows] = useState(null)
  const [err, setErr] = useState('')

  useEffect(() => {
    let alive = true
    host
      .request('session.list', { limit: 12 })
      .then(r => {
        if (alive) setRows((r && r.sessions) || [])
      })
      .catch(e => {
        if (!alive) return
        setRows([])
        setErr(String((e && e.message) || e))
      })
    return () => {
      alive = false
    }
  }, [])

  const items = [
    jsx(
      'div',
      {
        style: { padding: '4px 7px', fontSize: '0.6875rem', color: 'var(--ui-text-quaternary)' },
        children: 'Recent sessions'
      },
      'hdr'
    )
  ]

  if (rows === null) {
    items.push(
      jsx(
        'div',
        {
          style: { padding: '6px 7px', fontSize: '0.75rem', color: 'var(--ui-text-quaternary)' },
          children: 'Loading…'
        },
        'loading'
      )
    )
  } else if (rows.length === 0) {
    items.push(
      jsx(
        'div',
        {
          style: { padding: '6px 7px', fontSize: '0.75rem', color: 'var(--ui-text-quaternary)' },
          children: err ? 'Failed: ' + err : 'No sessions'
        },
        'empty'
      )
    )
  } else {
    for (const s of rows) {
      items.push(
        jsx(
          'button',
          {
            type: 'button',
            onClick: () => {
              haptic('tap')
              if (s && s.id) host.navigate('/' + s.id)
              onClose()
            },
            style: {
              display: 'block',
              width: '100%',
              textAlign: 'left',
              padding: '5px 7px',
              fontSize: '0.75rem',
              color: 'var(--ui-text-secondary)',
              background: 'transparent',
              border: 'none',
              borderRadius: '4px',
              cursor: 'pointer',
              whiteSpace: 'nowrap',
              overflow: 'hidden',
              textOverflow: 'ellipsis'
            },
            onMouseEnter: e => {
              e.currentTarget.style.background = 'var(--chrome-action-hover)'
            },
            onMouseLeave: e => {
              e.currentTarget.style.background = 'transparent'
            },
            children: (s.title || s.id) + (s.model ? '  · ' + s.model : '')
          },
          s.id
        )
      )
    }
  }

  return jsx('div', {
    style: {
      position: 'absolute',
      bottom: '100%',
      right: 0,
      marginBottom: '4px',
      width: '320px',
      maxHeight: '320px',
      overflowY: 'auto',
      padding: '4px',
      background: 'var(--ui-bg-elevated, var(--ui-bg))',
      border: '1px solid var(--ui-stroke-secondary)',
      borderRadius: '6px',
      boxShadow: '0 8px 24px rgba(0,0,0,0.35)',
      zIndex: 60
    },
    children: items
  })
}

function StatusBarChip() {
  const model = useValue(host.state.model)
  const live = useValue(host.state.focusedUsage)
  const busy = useValue(host.state.busy)
  const runtimeId = useValue(host.state.focusedSessionId)
  const [snapshot, setSnapshot] = useState(null)
  const [open, setOpen] = useState(false)

  useEffect(() => {
    let alive = true
    const tick = () => {
      if (!runtimeId) return
      host
        .request('session.usage', { session_id: runtimeId })
        .then(u => {
          if (alive && u) setSnapshot(u)
        })
        .catch(() => {})
    }
    tick()
    const id = setInterval(tick, 5000)
    return () => {
      alive = false
      clearInterval(id)
    }
  }, [runtimeId])

  const u = merge(live, snapshot)
  const pct = num(u.context_percent)
  const used = num(u.context_used) || 0
  const max = num(u.context_max) || 0
  const cache = num(u.cache_hit_pct)
  const tps = num(u.avg_tps)

  const segs = []
  if (model) segs.push(String(model).split('/').pop())
  if (pct != null) segs.push('[' + contextBar(pct) + '] ' + (u.context_estimated ? '~' : '') + Math.round(pct) + '%')
  if (max > 0) segs.push(kfmt(used) + '/' + kfmt(max))
  if (cache != null) segs.push('◎ ' + Math.round(cache) + '%')
  if (tps != null && tps > 0) segs.push('↑ ' + Math.round(tps) + ' t/s')
  segs.push('↑' + kfmt(u.input) + ' ↓' + kfmt(u.output))
  const text = segs.join('  │  ')

  const detail =
    'model: ' + (model || '?') +
    '\ncontext: ' + kfmt(used) + ' / ' + kfmt(max) + ' (' + (pct == null ? '?' : Math.round(pct)) + '%)' +
    (cache != null ? '\ncache hit: ' + Math.round(cache) + '%' : '') +
    (tps != null ? '\nspeed: ' + Math.round(tps) + ' t/s' : '') +
    '\ntokens: ↑' + kfmt(u.input) + ' ↓' + kfmt(u.output) +
    (num(u.cost_usd) != null ? '\ncost: $' + Number(u.cost_usd).toFixed(4) : '')

  return jsxs('div', {
    style: { position: 'relative', display: 'inline-flex', alignItems: 'center', height: '100%' },
    children: [
      jsx('button', {
        type: 'button',
        title: detail,
        onClick: () => {
          haptic('tap')
          host.notify({ kind: 'info', message: detail })
        },
        style: {
          ...chipBtn,
          maxWidth: '620px',
          overflow: 'hidden',
          whiteSpace: 'nowrap',
          textOverflow: 'ellipsis',
          fontVariantNumeric: 'tabular-nums'
        },
        children: text
      }),
      jsx('button', {
        type: 'button',
        title: 'New chat',
        onClick: () => {
          haptic('tap')
          host.navigate('/')
        },
        style: chipBtn,
        children: '＋'
      }),
      jsx('button', {
        type: 'button',
        title: busy ? 'Stop the current turn' : 'Nothing running',
        disabled: !busy,
        onClick: () => {
          if (!busy) return
          haptic('tap')
          host.request('session.interrupt', { session_id: runtimeId }).catch(() => {})
        },
        style: {
          ...chipBtn,
          color: busy ? 'var(--ui-warn, var(--ui-text))' : 'var(--ui-text-quaternary)',
          cursor: busy ? 'pointer' : 'default'
        },
        children: '■'
      }),
      jsx('button', {
        type: 'button',
        title: 'Recent sessions',
        onClick: () => {
          haptic('tap')
          setOpen(v => !v)
        },
        style: chipBtn,
        children: '☰'
      }),
      open ? jsx(SessionsList, { onClose: () => setOpen(false) }) : null
    ]
  })
}

export default {
  id: ID,
  name: 'Desktop Status Bar',
  register(ctx) {
    ctx.register({
      id: 'chip',
      area: STATUSBAR_AREAS.right,
      order: 140,
      render: () => jsx(StatusBarChip, {})
    })
  }
}
