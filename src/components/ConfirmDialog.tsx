'use client';

import { useEffect } from 'react';

interface Props {
  title: string;
  message: string;
  confirmLabel?: string;
  onConfirm: () => void;
  onCancel: () => void;
}

export default function ConfirmDialog({
  title,
  message,
  confirmLabel = 'Delete',
  onConfirm,
  onCancel,
}: Props) {
  useEffect(() => {
    const cancelOnEscape = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        onCancel();
      }
    };
    window.addEventListener('keydown', cancelOnEscape);
    return () => window.removeEventListener('keydown', cancelOnEscape);
  }, [onCancel]);

  return (
    <div
      className="fixed inset-0 z-50 flex items-center justify-center bg-black/50 p-4"
      onClick={onCancel}
    >
      <div
        className="w-full max-w-sm rounded-lg bg-[var(--bg-elev)] border border-[var(--border)] shadow-2xl"
        onClick={(e) => e.stopPropagation()}
      >
        <div className="p-4">
          <p className="text-sm font-medium">{title}</p>
          <p className="mt-1 text-xs text-[var(--muted-fg)]">{message}</p>
        </div>
        <div className="flex items-center justify-end gap-2 p-4 border-t border-[var(--border)]">
          {/* Cancel takes the focus: a stray Enter must not be what deletes something. */}
          <button
            autoFocus
            onClick={onCancel}
            className="px-3 py-1.5 text-sm text-[var(--muted-fg)] hover:bg-[var(--hover)] rounded-md"
          >
            Cancel
          </button>
          <button
            onClick={onConfirm}
            className="px-4 py-1.5 text-sm font-semibold rounded-md bg-[var(--danger)] text-white hover:opacity-90"
          >
            {confirmLabel}
          </button>
        </div>
      </div>
    </div>
  );
}
