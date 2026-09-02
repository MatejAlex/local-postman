'use client';

import { useState } from 'react';
import type { Environment } from '../lib/types';
import { newEnvironment } from '../lib/types';
import KeyValueEditor from './KeyValueEditor';

interface Props {
  environments: Environment[];
  activeId: string | null;
  onSelectActive: (id: string | null) => void;
  onSave: (env: Environment) => void;
  onDelete: (id: string) => void;
}

export default function EnvironmentManager({
  environments,
  activeId,
  onSelectActive,
  onSave,
  onDelete,
}: Props) {
  const [editing, setEditing] = useState<Environment | null>(null);

  const startNew = () => setEditing(newEnvironment());

  return (
    <div className="flex flex-col gap-2">
      <div className="flex items-center justify-between">
        <span className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)]">
          Environment
        </span>
        <button
          onClick={startNew}
          className="text-xs text-[var(--accent)] hover:opacity-80"
          title="New environment"
        >
          + New
        </button>
      </div>

      {/* Active environment picker */}
      <select
        value={activeId ?? ''}
        onChange={(e) => onSelectActive(e.target.value || null)}
        className="w-full px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] outline-none cursor-pointer"
      >
        <option value="">No environment</option>
        {environments.map((env) => (
          <option key={env.id} value={env.id}>
            {env.name}
          </option>
        ))}
      </select>

      {/* Quick list: clicking a row activates it, same as the picker above.
          It used to be display-only, which read as a list of radio buttons that
          did nothing: you clicked an environment, nothing moved, and every
          {{variable}} kept resolving against whatever the dropdown still said. */}
      <div className="flex flex-col gap-0.5">
        {environments.map((env) => (
          <div
            key={env.id}
            onClick={() => onSelectActive(env.id)}
            className={`group flex items-center gap-2 px-2 py-1 rounded-md cursor-pointer ${
              activeId === env.id ? 'bg-[var(--accent-soft)]' : 'hover:bg-[var(--hover)]'
            }`}
            title={activeId === env.id ? 'Active environment' : `Use ${env.name}`}
          >
            <span className="w-2.5 h-2.5 rounded-full shrink-0" style={{ background: env.color }} />
            <span
              className={`flex-1 text-sm truncate ${
                activeId === env.id ? 'text-[var(--fg)] font-medium' : 'text-[var(--muted-fg)]'
              }`}
            >
              {env.name}
            </span>
            <button
              onClick={(e) => {
                e.stopPropagation();
                setEditing(env);
              }}
              className="opacity-0 group-hover:opacity-100 text-xs text-[var(--muted-fg)] hover:text-[var(--fg)]"
            >
              Edit
            </button>
          </div>
        ))}
      </div>

      {editing && (
        <EnvironmentModal
          env={editing}
          isNew={!environments.some((e) => e.id === editing.id)}
          onClose={() => setEditing(null)}
          onSave={(e) => {
            onSave(e);
            setEditing(null);
          }}
          onDelete={(id) => {
            onDelete(id);
            setEditing(null);
          }}
        />
      )}
    </div>
  );
}

function EnvironmentModal({
  env,
  isNew,
  onClose,
  onSave,
  onDelete,
}: {
  env: Environment;
  isNew: boolean;
  onClose: () => void;
  onSave: (env: Environment) => void;
  onDelete: (id: string) => void;
}) {
  const [draft, setDraft] = useState<Environment>(env);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onClose}
    >
      <div
        className="w-full max-w-lg rounded-lg bg-[var(--bg-elev)] border border-[var(--border)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="flex items-center gap-3 p-4 border-b border-[var(--border)]">
          <input
            type="color"
            value={draft.color}
            onChange={(e) => setDraft({ ...draft, color: e.target.value })}
            className="w-8 h-8 rounded cursor-pointer bg-transparent border border-[var(--border)]"
          />
          <input
            value={draft.name}
            onChange={(e) => setDraft({ ...draft, name: e.target.value })}
            placeholder="Environment name"
            className="flex-1 px-2 py-1.5 text-sm rounded-md bg-[var(--bg-elev-2)] border border-[var(--border)] focus:border-[var(--accent)] outline-none"
          />
        </div>

        <div className="p-4">
          <p className="text-xs font-semibold uppercase tracking-wide text-[var(--muted-fg)] mb-2">
            Variables — reference with {'{{key}}'}
          </p>
          <KeyValueEditor
            rows={draft.variables}
            onChange={(variables) => setDraft({ ...draft, variables })}
            keyPlaceholder="variable"
          />
        </div>

        <div className="flex items-center justify-between gap-2 p-4 border-t border-[var(--border)]">
          {!isNew ? (
            <button
              onClick={() => onDelete(draft.id)}
              className="px-3 py-1.5 text-sm text-[var(--danger)] hover:bg-[var(--hover)] rounded-md"
            >
              Delete
            </button>
          ) : (
            <span />
          )}
          <div className="flex gap-2">
            <button
              onClick={onClose}
              className="px-3 py-1.5 text-sm text-[var(--muted-fg)] hover:bg-[var(--hover)] rounded-md"
            >
              Cancel
            </button>
            <button
              onClick={() => onSave(draft)}
              className="px-4 py-1.5 text-sm font-semibold rounded-md bg-[var(--accent)] text-[var(--accent-fg)] hover:opacity-90"
            >
              Save
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
