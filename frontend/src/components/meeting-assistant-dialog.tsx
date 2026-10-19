import { useEffect, useRef, useState } from 'react'
import { MicIcon, SparklesIcon, SquareIcon } from 'lucide-react'

import { Button } from '@/components/ui/button'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Field, FieldDescription, FieldError, FieldLabel } from '@/components/ui/field'
import { Textarea } from '@/components/ui/textarea'
import { useDraftMeeting } from '@/hooks/queries'
import type { MeetingDraft } from '@/lib/api'

// Keeps the upload well under the API's 4 MB limit.
const MAX_RECORDING_SECONDS = 120
// Formats the backend accepts, best first; Safari records mp4, the rest webm.
const RECORDING_TYPES = ['audio/webm;codecs=opus', 'audio/webm', 'audio/mp4', 'audio/ogg']

const canRecord =
  typeof window !== 'undefined' &&
  typeof window.MediaRecorder !== 'undefined' &&
  Boolean(navigator.mediaDevices?.getUserMedia)

function formatSeconds(seconds: number): string {
  return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, '0')}`
}

type Props = {
  open: boolean
  onOpenChange: (open: boolean) => void
  /** Called with the parsed details; the caller opens the meeting form to confirm them. */
  onDraft: (draft: MeetingDraft) => void
}

/** Describe a meeting in words or by voice; the assistant fills in the meeting form. */
export function MeetingAssistantDialog({ open, onOpenChange, onDraft }: Props) {
  const [text, setText] = useState('')
  const [recording, setRecording] = useState(false)
  const [elapsed, setElapsed] = useState(0)
  const [micError, setMicError] = useState<string | null>(null)
  const recorderRef = useRef<MediaRecorder | null>(null)
  // Set when the dialog closes mid-recording, so the recording is thrown away.
  const discardRef = useRef(false)
  const draftMeeting = useDraftMeeting()

  const stopRecording = (discard = false) => {
    discardRef.current = discard
    if (recorderRef.current?.state === 'recording') recorderRef.current.stop()
  }

  // Closing throws away a recording in progress and leaves a clean dialog for next time.
  const close = () => {
    stopRecording(true)
    setText('')
    setMicError(null)
    draftMeeting.reset()
    onOpenChange(false)
  }

  useEffect(() => {
    if (!recording) return
    const timer = setInterval(() => setElapsed((s) => s + 1), 1000)
    return () => clearInterval(timer)
  }, [recording])

  useEffect(() => {
    if (elapsed >= MAX_RECORDING_SECONDS) stopRecording()
  }, [elapsed])

  const submit = (input: { text: string } | { audio: Blob }) => {
    draftMeeting.mutate(input, {
      onSuccess: (draft) => {
        close()
        onDraft(draft)
      },
    })
  }

  const startRecording = async () => {
    setMicError(null)
    draftMeeting.reset()
    let stream: MediaStream
    try {
      stream = await navigator.mediaDevices.getUserMedia({ audio: true })
    } catch {
      setMicError('Microphone access was denied. Allow it in the browser, or type instead.')
      return
    }
    const mimeType = RECORDING_TYPES.find((type) => MediaRecorder.isTypeSupported(type))
    const recorder = new MediaRecorder(stream, mimeType ? { mimeType } : undefined)
    const chunks: Blob[] = []
    recorder.ondataavailable = (event) => {
      if (event.data.size > 0) chunks.push(event.data)
    }
    recorder.onstop = () => {
      stream.getTracks().forEach((track) => track.stop())
      recorderRef.current = null
      setRecording(false)
      if (discardRef.current || chunks.length === 0) return
      submit({ audio: new Blob(chunks, { type: recorder.mimeType }) })
    }
    discardRef.current = false
    recorderRef.current = recorder
    setElapsed(0)
    recorder.start()
    setRecording(true)
  }

  const busy = draftMeeting.isPending
  const error = micError ?? draftMeeting.error?.message

  return (
    <Dialog open={open} onOpenChange={(next) => !next && close()}>
      <DialogContent className="sm:max-w-lg">
        <DialogHeader>
          <DialogTitle>Create meeting with AI</DialogTitle>
          <DialogDescription>
            Describe the meeting by typing or speaking. You&apos;ll check the details before it is
            created.
          </DialogDescription>
        </DialogHeader>

        <form
          id="meeting-assistant-form"
          onSubmit={(event) => {
            event.preventDefault()
            if (text.trim()) submit({ text: text.trim() })
          }}
        >
          <Field data-invalid={Boolean(error)}>
            <FieldLabel htmlFor="meeting-assistant-text">What&apos;s the meeting?</FieldLabel>
            <Textarea
              id="meeting-assistant-text"
              rows={4}
              maxLength={5000}
              placeholder="Sprint planning tomorrow 3–4pm in room 204 with Olena and Taras"
              value={text}
              onChange={(event) => setText(event.target.value)}
              onKeyDown={(event) => {
                if (event.key === 'Enter' && (event.metaKey || event.ctrlKey)) {
                  event.currentTarget.form?.requestSubmit()
                }
              }}
              disabled={busy || recording}
              autoFocus
            />
            {recording ? (
              <FieldDescription className="flex items-center gap-2">
                <span className="size-2 animate-pulse rounded-full bg-destructive" />
                Listening… {formatSeconds(elapsed)} / {formatSeconds(MAX_RECORDING_SECONDS)}
              </FieldDescription>
            ) : busy ? (
              <FieldDescription>Reading the details…</FieldDescription>
            ) : null}
            {error && <FieldError>{error}</FieldError>}
          </Field>
        </form>

        <DialogFooter className="sm:justify-between">
          {canRecord ? (
            recording ? (
              <Button type="button" variant="destructive" onClick={() => stopRecording()}>
                <SquareIcon />
                Stop and fill in
              </Button>
            ) : (
              <Button type="button" variant="outline" onClick={startRecording} disabled={busy}>
                <MicIcon />
                Speak
              </Button>
            )
          ) : (
            <span />
          )}
          <Button
            type="submit"
            form="meeting-assistant-form"
            disabled={busy || recording || !text.trim()}
          >
            <SparklesIcon />
            {busy ? 'Filling in…' : 'Fill in the form'}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  )
}
