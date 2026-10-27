import { useRef, useState } from 'react'
import { Loader2Icon } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { useSaveAgenda } from '@/hooks/queries'
import { parseAgenda, type Meeting, type ParseResult } from '@/lib/api'

type ItemDraft = { topic: string; owner: string; minutes: string }
type ActionDraft = { task: string; owner: string; due: string }
type Draft = { items: ItemDraft[]; actions: ActionDraft[] }
type Phase = 'input' | 'loading' | 'review'

const MAX_CHARS = 10_000
const inputClass =
  'w-full rounded-md border border-input bg-transparent px-2 py-1 text-sm outline-none focus-visible:ring-2 focus-visible:ring-ring'

function toDraft(result: ParseResult): Draft {
  return {
    items: result.agenda.items.map((i) => ({
      topic: i.topic,
      owner: i.owner ?? '',
      minutes: i.minutes?.toString() ?? '',
    })),
    actions: result.agenda.action_items.map((a) => ({
      task: a.task,
      owner: a.owner ?? '',
      due: a.due ?? '',
    })),
  }
}

type FieldProps = {
  label: string
  value: string
  original: string | undefined
  onChange: (value: string) => void
  type?: string
}

// A field the model filled keeps the "suggested" badge until the user changes it.
function Field({ label, value, original, onChange, type = 'text' }: FieldProps) {
  const suggested = value !== '' && value === original
  return (
    <label className="flex flex-col gap-1 text-xs text-muted-foreground">
      <span>
        {label}
        {suggested && (
          <span className="ml-2 rounded bg-muted px-1.5 py-0.5 text-[10px] uppercase">
            suggested
          </span>
        )}
      </span>
      <input
        className={inputClass}
        type={type}
        value={value}
        onChange={(e) => onChange(e.target.value)}
      />
    </label>
  )
}

type Props = {
  meeting: Meeting
  open: boolean
  onOpenChange: (open: boolean) => void
}

export function AgendaPasteDialog({ meeting, open, onOpenChange }: Props) {
  const [phase, setPhase] = useState<Phase>('input')
  const [text, setText] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [result, setResult] = useState<ParseResult | null>(null)
  const [original, setOriginal] = useState<Draft | null>(null)
  const [draft, setDraft] = useState<Draft | null>(null)
  const controller = useRef<AbortController | null>(null)
  const save = useSaveAgenda()

  function reset() {
    controller.current?.abort()
    setPhase('input')
    setText('')
    setError(null)
    setResult(null)
    setOriginal(null)
    setDraft(null)
  }

  function handleOpenChange(next: boolean) {
    if (!next) reset()
    onOpenChange(next)
  }

  async function handleParse() {
    setError(null)
    setPhase('loading')
    controller.current = new AbortController()
    try {
      const parsed = await parseAgenda(text, controller.current.signal)
      setResult(parsed)
      setOriginal(toDraft(parsed))
      setDraft(toDraft(parsed))
      setPhase('review')
    } catch (e) {
      if (e instanceof DOMException && e.name === 'AbortError') return
      setError(e instanceof Error ? e.message : 'Something went wrong')
      setPhase('input')
    }
  }

  function handleCancel() {
    controller.current?.abort()
    setPhase('input')
  }

  async function handleSave() {
    if (!draft || !result) return
    setError(null)
    try {
      await save.mutateAsync({
        id: meeting.id,
        agenda: {
          // An item with an empty topic or task counts as deleted.
          items: draft.items
            .filter((i) => i.topic.trim())
            .map((i) => ({
              topic: i.topic.trim(),
              owner: i.owner.trim() || null,
              minutes: i.minutes ? Number(i.minutes) : null,
            })),
          action_items: draft.actions
            .filter((a) => a.task.trim())
            .map((a) => ({
              task: a.task.trim(),
              owner: a.owner.trim() || null,
              due: a.due || null,
            })),
        },
        ai_suggestion: result.agenda,
        model: result.model,
        prompt_version: result.prompt_version,
      })
      handleOpenChange(false)
    } catch (e) {
      setError(e instanceof Error ? e.message : 'Could not save the agenda')
    }
  }

  function setItem(index: number, patch: Partial<ItemDraft>) {
    setDraft((d) => d && { ...d, items: d.items.map((x, i) => (i === index ? { ...x, ...patch } : x)) })
  }
  function setAction(index: number, patch: Partial<ActionDraft>) {
    setDraft((d) => d && { ...d, actions: d.actions.map((x, i) => (i === index ? { ...x, ...patch } : x)) })
  }

  return (
    <Dialog open={open} onOpenChange={handleOpenChange}>
      <DialogContent className="max-h-[calc(100svh-2rem)] overflow-y-auto sm:max-w-xl">
        <DialogHeader>
          <DialogTitle>Paste an agenda</DialogTitle>
          <DialogDescription>
            Paste an email or notes. The AI suggests an agenda, you check it and press Save.
          </DialogDescription>
        </DialogHeader>

        {phase !== 'review' && (
          <div className="flex flex-col gap-2">
            <textarea
              className={`${inputClass} min-h-40`}
              placeholder="Пн 10:00, синк по прайсингу, 45 хв. 1) ..."
              value={text}
              maxLength={MAX_CHARS}
              disabled={phase === 'loading'}
              onChange={(e) => setText(e.target.value)}
            />
            <p className="text-xs text-muted-foreground">
              {text.length} / {MAX_CHARS}
            </p>
          </div>
        )}

        {phase === 'loading' && (
          <p className="flex items-center gap-2 text-sm text-muted-foreground">
            <Loader2Icon className="size-4 animate-spin" />
            Parsing… this takes 2–8 seconds
          </p>
        )}

        {phase === 'review' && draft && original && (
          <div className="flex flex-col gap-5">
            <div className="flex flex-col gap-3">
              <h3 className="text-lg">Agenda items</h3>
              {draft.items.length === 0 && (
                <p className="text-sm text-muted-foreground">No agenda items were found.</p>
              )}
              {draft.items.map((item, i) => (
                <div key={i} className="grid grid-cols-[2fr_1fr_5rem] gap-2">
                  <Field label="Topic" value={item.topic} original={original.items[i]?.topic}
                    onChange={(v) => setItem(i, { topic: v })} />
                  <Field label="Owner" value={item.owner} original={original.items[i]?.owner}
                    onChange={(v) => setItem(i, { owner: v })} />
                  <Field label="Min" type="number" value={item.minutes}
                    original={original.items[i]?.minutes}
                    onChange={(v) => setItem(i, { minutes: v })} />
                </div>
              ))}
            </div>

            <div className="flex flex-col gap-3">
              <h3 className="text-lg">Action items</h3>
              {draft.actions.length === 0 && (
                <p className="text-sm text-muted-foreground">No action items were found.</p>
              )}
              {draft.actions.map((a, i) => (
                <div key={i} className="grid grid-cols-[2fr_1fr_9rem] gap-2">
                  <Field label="Task" value={a.task} original={original.actions[i]?.task}
                    onChange={(v) => setAction(i, { task: v })} />
                  <Field label="Owner" value={a.owner} original={original.actions[i]?.owner}
                    onChange={(v) => setAction(i, { owner: v })} />
                  <Field label="Due" type="date" value={a.due} original={original.actions[i]?.due}
                    onChange={(v) => setAction(i, { due: v })} />
                </div>
              ))}
            </div>
            <p className="text-xs text-muted-foreground">
              Clear a topic or task to remove that row. Check dates carefully, the model can get them wrong.
            </p>
          </div>
        )}

        {error && <p className="text-sm text-destructive">{error}</p>}

        <DialogFooter>
          {phase === 'input' && (
            <Button onClick={handleParse} disabled={!text.trim()}>
              Parse
            </Button>
          )}
          {phase === 'loading' && (
            <Button variant="ghost" onClick={handleCancel}>
              Cancel
            </Button>
          )}
          {phase === 'review' && (
            <>
              <Button variant="ghost" onClick={() => setPhase('input')}>
                Back
              </Button>
              <Button onClick={handleSave} disabled={save.isPending}>
                Save
              </Button>
            </>
          )}
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
