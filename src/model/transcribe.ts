// 转记：实际音高不动，只把全曲统一到目标首调，并按指定规则重算唱名与升降号。

import type { Key, ScoreDoc, Song } from "./doc";
import { type EditHooks, midiOfPitch, respellMeasure, spellMidi } from "./edit";
import { AccidentalCarry, assignDegrees, continuesMeasure, keySpelling } from "./jianpu";

export type TranscriptionSpelling = "key" | "sharp" | "flat";

export interface TranscriptionOptions {
  /** 目标调号的五度圈位置（-7..7）；界面写作 `1=?`。 */
  fifths: number;
  /** 临时半音按目标调号、统一升号或统一降号拼写。 */
  spelling: TranscriptionSpelling;
}

export interface TranscriptionResult {
  notes: number;
}

/**
 * 简谱来源通常只有 degree。先按原调号把绝对音高补齐，后面换调号时才不会改变实际音高。
 * 规则与 `xmlproject.ts` 导出 MusicXML 时一致：临时记号在小节内延续，八度谱号还原为实际八度。
 */
function fillPitches(song: Song): void {
  const initialKey = song.key ?? { fifths: 0 };
  for (const part of song.parts) {
    let key = initialKey;
    const clefOctaves = new Map<number, number>();
    let carries = new Map<number, AccidentalCarry>();
    part.measures.forEach((measure, mi) => {
      if (measure.attrs?.key) key = measure.attrs.key;
      for (const clef of measure.attrs?.clefs ?? []) clefOctaves.set(clef.staff ?? 1, clef.octaveChange ?? 0);
      if (!continuesMeasure(part.measures[mi - 1], measure)) carries = new Map();
      for (const element of measure.elements) {
        if (element.kind !== "chord") continue;
        let carry = carries.get(element.staff);
        if (!carry) carries.set(element.staff, (carry = new AccidentalCarry()));
        for (const note of element.notes) {
          if (!note.degree || note.degree.number === 0) continue;
          const pitch = carry.pitch(note.degree, key);
          pitch.octave += clefOctaves.get(element.staff) ?? 0;
          if (!note.pitch) note.pitch = pitch;
        }
      }
    });
  }
}

function targetKey(fifths: number): Key {
  const key: Key = { fifths, mode: "major", tonicDegree: "1" };
  key.spelling = keySpelling(key);
  return key;
}

function clearLaterKeys(song: Song, key: Key): void {
  song.key = { ...key };
  for (const part of song.parts) {
    const first = part.measures[0];
    if (first) first.attrs = { ...(first.attrs ?? {}), key: { ...key } };
    part.measures.forEach((measure, mi) => {
      if (mi > 0 && measure.attrs?.key) {
        delete measure.attrs.key;
        if (Object.keys(measure.attrs).length === 0) delete measure.attrs;
      }
      if (measure.laterAttrs) {
        for (const later of measure.laterAttrs) delete later.attrs.key;
        measure.laterAttrs = measure.laterAttrs.filter((later) => Object.keys(later.attrs).length > 0);
        if (measure.laterAttrs.length === 0) delete measure.laterAttrs;
      }
    });
  }
}

/**
 * 就地转记整份文档。所有歌曲、声部、声线、和弦音与倚音都处理；MIDI 音高保持不变。
 * 再次用同一选项执行是幂等的。
 */
export function transcribeScore(doc: ScoreDoc, options: TranscriptionOptions, hooks: EditHooks = {}): TranscriptionResult {
  const fifths = Math.max(-7, Math.min(7, Math.trunc(options.fifths)));
  const key = targetKey(fifths);
  let notes = 0;
  for (const song of doc.songs) {
    fillPitches(song);
    clearLaterKeys(song, key);
    for (const part of song.parts) {
      for (const measure of part.measures) {
        for (const element of measure.elements) {
          if (element.kind !== "chord") continue;
          let pitched = false;
          for (const note of element.notes) {
            if (!note.pitch) continue;
            notes++;
            pitched = true;
            if (options.spelling === "key" && fifths === 0) continue;
            const sign = options.spelling === "sharp" ? 1 : options.spelling === "flat" ? -1 : Math.sign(fifths);
            note.pitch = spellMidi(midiOfPitch(note.pitch), fifths, sign);
          }
          if (pitched) hooks.forgetStem?.(element);
        }
        respellMeasure(measure, key);
      }
      assignDegrees(part, key);
    }
    hooks.forgetLayout?.(song);
  }
  return { notes };
}
