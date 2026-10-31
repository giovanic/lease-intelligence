/** A record status pill; `tone` picks the color, `label` is what is shown. */
export function StatusBadge({ label, tone }: { label: string; tone: 'positive' | 'neutral' | 'muted' }) {
  return <span className={`badge badge--${tone}`}>{label}</span>
}
