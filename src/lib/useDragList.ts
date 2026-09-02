'use client';

import { useState } from 'react';

/**
 * Reordering for one flat list, over the browser's own drag events.
 *
 * No library: HTML5 drag-and-drop already does the hard part, and one list of
 * rows does not need a physics engine.
 *
 * Two things here are load-bearing and both were wrong in the first cut:
 *
 * **The source index travels in the drag payload, not in React state.** Setting
 * state on `dragstart` and reading it on `drop` looks obvious and loses the
 * race - the drop can arrive before React has committed the update, and then
 * nothing moves. `dataTransfer` is the channel the browser provides for exactly
 * this, and it is already correct across re-renders.
 *
 * **Each list gets its own MIME type.** Request rows are nested inside
 * collection rows, so their drag events bubble into the collection list's
 * handlers. Typing the payload means the outer list simply does not recognise a
 * request being dragged, which is sturdier than relying on `stopPropagation`
 * alone (we do both).
 *
 * State is kept only for the drop-target outline, where being a frame late
 * costs nothing.
 */
export function useDragList(kind: string, onReorder: (from: number, to: number) => void) {
  const [overIndex, setOverIndex] = useState<number | null>(null);
  const mime = `application/x-local-postman-${kind}`;

  const carriesOurs = (e: React.DragEvent) => e.dataTransfer.types.includes(mime);

  const itemProps = (index: number) => ({
    draggable: true,
    onDragStart: (e: React.DragEvent) => {
      e.stopPropagation();
      e.dataTransfer.effectAllowed = 'move';
      e.dataTransfer.setData(mime, String(index));
      // Firefox ignores a drag carrying no text/plain at all.
      e.dataTransfer.setData('text/plain', String(index));
    },
    onDragOver: (e: React.DragEvent) => {
      if (!carriesOurs(e)) return;
      e.stopPropagation();
      // Without preventDefault the browser refuses the drop outright.
      e.preventDefault();
      e.dataTransfer.dropEffect = 'move';
      if (overIndex !== index) setOverIndex(index);
    },
    onDragLeave: () => setOverIndex((current) => (current === index ? null : current)),
    onDrop: (e: React.DragEvent) => {
      if (!carriesOurs(e)) return;
      e.preventDefault();
      e.stopPropagation();
      const from = Number(e.dataTransfer.getData(mime));
      setOverIndex(null);
      if (Number.isInteger(from) && from !== index) onReorder(from, index);
    },
    onDragEnd: () => setOverIndex(null),
  });

  return { itemProps, overIndex };
}
