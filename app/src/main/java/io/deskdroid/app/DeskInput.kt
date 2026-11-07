package io.deskdroid.app

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.text.Editable
import android.text.InputType
import android.text.Selection
import android.view.KeyEvent
import android.view.View
import android.view.inputmethod.BaseInputConnection
import android.view.inputmethod.EditorInfo
import android.view.inputmethod.InputConnection
import android.view.inputmethod.InputMethodManager
import java.lang.ref.WeakReference

/**
 * The phone's keyboard as a real input method for desktop text fields: swipe
 * typing, autocorrect and word suggestions (Gboard, SwiftKey...).
 *
 * Android keyboards only offer those to an editor that tells them the text
 * around the cursor and takes words, not keys. So while a desktop text field
 * has the focus (KWin tells us, with its kind: protocol.h's IME), the
 * desktop's view is such an editor: [Connection] keeps a copy of the field's
 * text around the cursor (the app reports it through KWin: SURROUNDING), lets
 * the keyboard edit that copy like any Android text box (corrections, the
 * space bar's cursor slide), and after each edit sends the field the
 * difference: the word being composed as KWin preedit text (underlined in the
 * field), finished words as commits, and Backspace or arrow keys for what the
 * keyboard took back or moved over. KWin hands those to the app over Wayland
 * text-input like a desktop input method's (add-to-kwin.py).
 *
 * Elsewhere (no text field, a terminal, or Plain keys in the DD menu) the
 * keyboard types keys as before (TYPE_NULL).
 *
 * The keyboard isn't restarted while the field keeps the focus: a restarted
 * keyboard typed the word it was composing a second time. A click or a real
 * keyboard's key instead ends the composing word, and the copy follows the
 * field's text again.
 */
object DeskInput {
    // protocol.h's NDESK_TEXT_*, NDESK_PURPOSE_* and NDESK_HINT_*.
    private const val TEXT_COMMIT = 1
    private const val TEXT_PREEDIT = 2
    private const val P_DIGITS = 2
    private const val P_NUMBER = 3
    private const val P_PHONE = 4
    private const val P_URL = 5
    private const val P_EMAIL = 6
    private const val P_NAME = 7
    private const val P_PASSWORD = 8
    private const val P_DATE = 9
    private const val P_TIME = 10
    private const val P_DATETIME = 11
    private const val P_TERMINAL = 12
    private const val P_PIN = 13
    private const val H_AUTO_CAPITALIZATION = 1 shl 2
    private const val H_UPPERCASE = 1 shl 4
    private const val H_HIDDEN = 1 shl 6
    private const val H_SENSITIVE = 1 shl 7
    private const val H_MULTILINE = 1 shl 9

    // The focused desktop text field, as KWin last told us (main thread).
    private var field = false
    private var purpose = 0
    private var hints = 0
    private val main = Handler(Looper.getMainLooper())
    private val views = mutableListOf<WeakReference<View>>()
    private var live: Connection? = null
    // The field's text around the cursor as the app last reported it, with
    // the cursor and the selection's other end; null until it reports.
    private var reported: Triple<String, Int, Int>? = null
    // Whether the copy may take what the app reports: from the field's
    // focus, a click or a real key until the keyboard first types. Reports
    // after that can be from before its text landed (adopting one made
    // the keyboard type the same letters again), and the copy knows better.
    private var listening = true

    /** From the compositor (NativeDesk.onIme), on the main thread. */
    fun onField(active: Boolean, purpose: Int, hints: Int) {
        if (active == field && purpose == this.purpose && hints == this.hints) return
        if (active != field) AppLog.i("Phone keyboard: desktop text field ${if (active) "focused (purpose $purpose, hints $hints)" else "left"}")
        field = active; this.purpose = purpose; this.hints = hints
        // A new field: the old copy is no use there (its composing word went
        // with the old field when it was clicked away from).
        reported = null
        listening = true
        live?.dead = true
        live = null
        restart()
    }

    /** From the compositor (NativeDesk.onSurrounding): the field's text around the cursor. */
    fun onSurrounding(text: String, cursor: Int, anchor: Int) {
        val r = Triple(text, cursor.coerceIn(0, text.length), anchor.coerceIn(0, text.length))
        reported = r
        if (listening) live?.adopt(r.first, r.second, r.third)
    }

    /**
     * A click in the desktop or a key from a real keyboard: the field's cursor
     * may move where the copy can't follow. The word being composed is
     * finished where it is (before the click lands), and the copy takes the
     * field's text as the app reports it next.
     */
    fun interrupted(click: Boolean = true) {
        val c = live ?: return
        c.reset()
    }

    /** Plain keys or swipe typing picked in the DD menu: the keyboard takes it now. */
    fun prefChanged(v: View) {
        live?.let { it.reset(); it.dead = true }
        live = null
        if (views.none { it.get() === v }) views += WeakReference(v)
        restart()
    }

    private fun restart() {
        views.removeAll { it.get() == null }
        for (ref in views) {
            val v = ref.get() ?: continue
            if (!v.isAttachedToWindow) continue
            v.context.getSystemService(InputMethodManager::class.java)?.restartInput(v)
        }
    }

    /** The desktop view's onCreateInputConnection. */
    fun connect(v: View, info: EditorInfo): InputConnection {
        if (views.none { it.get() === v }) views += WeakReference(v)
        live?.dead = true
        live = null
        info.initialSelStart = 0
        info.initialSelEnd = 0
        if (!field || purpose == P_TERMINAL || !Prefs.smartTyping(v.context)) {
            info.inputType = InputType.TYPE_NULL
            info.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN
            return BaseInputConnection(v, false)
        }
        info.inputType = inputType()
        info.imeOptions = EditorInfo.IME_FLAG_NO_FULLSCREEN or EditorInfo.IME_FLAG_NO_EXTRACT_UI or
            EditorInfo.IME_FLAG_NO_ENTER_ACTION or EditorInfo.IME_ACTION_NONE or
            (if (private()) EditorInfo.IME_FLAG_NO_PERSONALIZED_LEARNING else 0)
        val c = Connection(v)
        if (listening) reported?.let { (t, cursor, anchor) ->
            c.adopt(t, cursor, anchor, notify = false)
            info.initialSelStart = minOf(cursor, anchor)
            info.initialSelEnd = maxOf(cursor, anchor)
            if (android.os.Build.VERSION.SDK_INT >= 30) info.setInitialSurroundingText(t)
        }
        live = c
        return c
    }

    private fun private() = purpose == P_PASSWORD || purpose == P_PIN || hints and (H_HIDDEN or H_SENSITIVE) != 0

    private fun inputType(): Int = when (purpose) {
        P_DIGITS -> InputType.TYPE_CLASS_NUMBER
        P_PIN -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_VARIATION_PASSWORD
        P_NUMBER -> InputType.TYPE_CLASS_NUMBER or InputType.TYPE_NUMBER_FLAG_SIGNED or InputType.TYPE_NUMBER_FLAG_DECIMAL
        P_PHONE -> InputType.TYPE_CLASS_PHONE
        P_DATE -> InputType.TYPE_CLASS_DATETIME or InputType.TYPE_DATETIME_VARIATION_DATE
        P_TIME -> InputType.TYPE_CLASS_DATETIME or InputType.TYPE_DATETIME_VARIATION_TIME
        P_DATETIME -> InputType.TYPE_CLASS_DATETIME
        else -> {
            var t = InputType.TYPE_CLASS_TEXT
            t = t or when {
                private() -> InputType.TYPE_TEXT_VARIATION_PASSWORD
                purpose == P_URL -> InputType.TYPE_TEXT_VARIATION_URI
                purpose == P_EMAIL -> InputType.TYPE_TEXT_VARIATION_EMAIL_ADDRESS
                purpose == P_NAME -> InputType.TYPE_TEXT_VARIATION_PERSON_NAME
                else -> InputType.TYPE_TEXT_VARIATION_NORMAL
            }
            if (private()) {
                t = t or InputType.TYPE_TEXT_FLAG_NO_SUGGESTIONS
            } else {
                // Swipe typing, corrections and the suggestion strip.
                t = t or InputType.TYPE_TEXT_FLAG_AUTO_CORRECT
                if (hints and H_UPPERCASE != 0) t = t or InputType.TYPE_TEXT_FLAG_CAP_CHARACTERS
                else if (hints and H_AUTO_CAPITALIZATION != 0) t = t or InputType.TYPE_TEXT_FLAG_CAP_SENTENCES
            }
            if (hints and H_MULTILINE != 0) t = t or InputType.TYPE_TEXT_FLAG_MULTI_LINE
            t
        }
    }

    private fun key(code: Int, times: Int = 1) {
        if (times > 0) listening = false
        repeat(times) {
            NativeDesk.nativeKey(code, 0, true)
            NativeDesk.nativeKey(code, 0, false)
        }
    }

    private fun send(kind: Int, text: String, cursor: Int = 0) {
        listening = false
        NativeDesk.nativeText(kind, text.toByteArray(Charsets.UTF_8), cursor)
    }

    /** Types text into the field: commits, with Enter for each line break. */
    private fun type(text: String) {
        text.split('\n').forEachIndexed { i, line ->
            if (i > 0) key(KeyEvent.KEYCODE_ENTER)
            if (line.isNotEmpty()) send(TEXT_COMMIT, line)
        }
    }

    private fun points(s: CharSequence, from: Int = 0, to: Int = s.length) =
        if (to > from) Character.codePointCount(s, from, to) else 0

    /** Whether a split at [i] falls inside a surrogate pair. */
    private fun splits(s: CharSequence, i: Int) =
        i in 1 until s.length && Character.isLowSurrogate(s[i]) && Character.isHighSurrogate(s[i - 1])

    /**
     * The field as the phone's keyboard sees it: an Android editor over a copy
     * of the field's text around the cursor, mirrored into the desktop's field
     * after every edit (see [DeskInput]).
     */
    class Connection(private val view: View) : BaseInputConnection(view, true) {
        @Volatile var dead = false
        private val text: Editable = Editable.Factory.getInstance().newEditable("")
        // What the desktop's field has from us: text before and after its
        // cursor, and the word being composed there with its own cursor.
        private var before = ""
        private var after = ""
        private var preedit = ""
        private var preeditCursor = 0
        private var batch = 0
        // A selection in the field (from the app's report): typing replaces it
        // there, so the first edit deletes it with one Backspace.
        private var selLo = 0
        private var selHi = 0

        override fun getEditable(): Editable = text

        /**
         * The copy becomes the field's text as the app reports it, unless the
         * keyboard is mid-edit or composing (the field's own report leaves the
         * composing word out). [notify]: the keyboard hears the new cursor.
         */
        fun adopt(s: String, cursor: Int, anchor: Int, notify: Boolean = true) {
            if (dead || batch > 0 || preedit.isNotEmpty() || getComposingSpanStart(text) >= 0) return
            val lo = minOf(cursor, anchor)
            val hi = maxOf(cursor, anchor)
            if (s == before + after && cursor == before.length && lo == selLo && hi == selHi &&
                Selection.getSelectionStart(text) == anchor && Selection.getSelectionEnd(text) == cursor) return
            text.replace(0, text.length, s)
            Selection.setSelection(text, anchor, cursor)
            before = s.substring(0, cursor)
            after = s.substring(cursor)
            selLo = lo; selHi = hi
            if (notify) updated()
        }

        /**
         * A click or a key the copy can't follow: the composing word ends where
         * it is (the keyboard is told it's gone, so it doesn't type it again),
         * and the copy is empty until the app reports the field's text (KWin
         * reports it again after a click, changed or not).
         */
        fun reset() {
            if (dead) return
            if (preedit.isNotEmpty()) send(TEXT_COMMIT, preedit)
            preedit = ""; preeditCursor = 0
            batch = 0
            text.clear()
            before = ""; after = ""; selLo = 0; selHi = 0
            Selection.setSelection(text, 0)
            updated()
            listening = true
        }

        private fun updated() {
            view.context.getSystemService(InputMethodManager::class.java)?.updateSelection(
                view, Selection.getSelectionStart(text), Selection.getSelectionEnd(text),
                getComposingSpanStart(text), getComposingSpanEnd(text))
        }

        private inline fun edit(block: () -> Boolean): Boolean {
            if (dead) return false
            val r = block()
            changed()
            return r
        }

        private fun changed() {
            if (batch == 0 && !dead) mirror()
        }

        override fun beginBatchEdit(): Boolean {
            if (dead) return false
            batch++
            return true
        }

        override fun endBatchEdit(): Boolean {
            if (dead) return false
            if (batch > 0) batch--
            changed()
            return batch > 0
        }

        override fun commitText(t: CharSequence?, cursor: Int) = edit { super.commitText(t, cursor) }
        override fun setComposingText(t: CharSequence?, cursor: Int) = edit { super.setComposingText(t, cursor) }
        override fun setComposingRegion(start: Int, end: Int) = edit { super.setComposingRegion(start, end) }
        override fun finishComposingText() = edit { super.finishComposingText() }
        override fun setSelection(start: Int, end: Int) = edit { super.setSelection(start, end) }
        override fun replaceText(start: Int, end: Int, t: CharSequence, cursor: Int, attr: android.view.inputmethod.TextAttribute?) =
            edit { super.replaceText(start, end, t, cursor, attr) }

        /** The selection and composing word together: what deleting around the cursor deletes around. */
        private fun span(): Pair<Int, Int> {
            var lo = minOf(Selection.getSelectionStart(text), Selection.getSelectionEnd(text)).coerceAtLeast(0)
            var hi = maxOf(Selection.getSelectionStart(text), Selection.getSelectionEnd(text)).coerceAtLeast(0)
            val cs = getComposingSpanStart(text)
            val ce = getComposingSpanEnd(text)
            if (cs >= 0 && ce >= 0) { lo = minOf(lo, cs, ce); hi = maxOf(hi, cs, ce) }
            return lo.coerceAtMost(text.length) to hi.coerceAtMost(text.length)
        }

        override fun deleteSurroundingText(beforeLength: Int, afterLength: Int): Boolean {
            if (dead) return false
            // What's before the copy (typed before the field had the phone's
            // keyboard) is deleted with keys: the copy doesn't have it.
            val (lo, hi) = span()
            val extraBefore = (beforeLength - lo).coerceAtLeast(0)
            val extraAfter = (afterLength - (text.length - hi)).coerceAtLeast(0)
            val r = edit { super.deleteSurroundingText(beforeLength, afterLength) }
            key(KeyEvent.KEYCODE_DEL, extraBefore)
            key(KeyEvent.KEYCODE_FORWARD_DEL, extraAfter)
            return r
        }

        override fun deleteSurroundingTextInCodePoints(beforeLength: Int, afterLength: Int): Boolean {
            if (dead) return false
            val (lo, hi) = span()
            val extraBefore = (beforeLength - points(text, 0, lo)).coerceAtLeast(0)
            val extraAfter = (afterLength - points(text, hi)).coerceAtLeast(0)
            val r = edit { super.deleteSurroundingTextInCodePoints(beforeLength, afterLength) }
            key(KeyEvent.KEYCODE_DEL, extraBefore)
            key(KeyEvent.KEYCODE_FORWARD_DEL, extraAfter)
            return r
        }

        override fun performEditorAction(action: Int): Boolean {
            if (dead) return false
            enter()
            return true
        }

        /** Enter: the composing word finished, Enter pressed, and a fresh copy (a new line or a new field). */
        private fun enter() {
            super.finishComposingText()
            mirror()
            key(KeyEvent.KEYCODE_ENTER)
            reset() // a new line, or the form went: the app reports what's there now
        }

        override fun sendKeyEvent(e: KeyEvent): Boolean {
            if (dead) return false
            val down = e.action == KeyEvent.ACTION_DOWN
            if (e.action == KeyEvent.ACTION_MULTIPLE) {
                e.characters?.let { commitText(it, 1) }
                return true
            }
            val a = Selection.getSelectionStart(text).coerceAtLeast(0)
            val b = Selection.getSelectionEnd(text).coerceAtLeast(0)
            val (lo, hi) = minOf(a, b) to maxOf(a, b)
            val plain = !e.isCtrlPressed && !e.isAltPressed && !e.isMetaPressed
            when (e.keyCode) {
                // Keyboards that delete and move with keys: done on the copy
                // (which sends the field the same) while it has the text.
                KeyEvent.KEYCODE_DEL -> if (plain && (hi > lo || lo > 0)) {
                    if (down) edit {
                        if (hi > lo) text.delete(lo, hi) else text.delete(lo - Character.charCount(Character.codePointBefore(text, lo)), lo)
                        true
                    }
                    return true
                }
                KeyEvent.KEYCODE_FORWARD_DEL -> if (plain && (hi > lo || hi < text.length)) {
                    if (down) edit {
                        if (hi > lo) text.delete(lo, hi) else text.delete(hi, minOf(text.length, hi + Character.charCount(Character.codePointAt(text, hi))))
                        true
                    }
                    return true
                }
                KeyEvent.KEYCODE_DPAD_LEFT -> if (plain && !e.isShiftPressed && b > 0) {
                    if (down) edit {
                        super.finishComposingText()
                        Selection.setSelection(text, b - Character.charCount(Character.codePointBefore(text, b)))
                        true
                    }
                    return true
                }
                KeyEvent.KEYCODE_DPAD_RIGHT -> if (plain && !e.isShiftPressed && b < text.length) {
                    if (down) edit {
                        super.finishComposingText()
                        Selection.setSelection(text, b + Character.charCount(Character.codePointAt(text, b)))
                        true
                    }
                    return true
                }
                KeyEvent.KEYCODE_ENTER, KeyEvent.KEYCODE_NUMPAD_ENTER -> if (plain) {
                    if (down) enter()
                    return true
                }
            }
            // A character typed as a key (some keyboards' digits and symbols): text.
            val ch = e.unicodeChar
            if (plain && ch != 0 && (ch and KeyCharacterMapCombining) == 0 && e.keyCode != KeyEvent.KEYCODE_TAB) {
                if (down) commitText(String(Character.toChars(ch)), 1)
                return true
            }
            // Anything else (Tab, Esc, shortcuts...) goes to the desktop as it
            // is, and may move the field's cursor: the copy starts over.
            if (down) super.finishComposingText().also { mirror() }
            NativeDesk.nativeKey(e.keyCode, e.unicodeChar, down)
            if (!down && !KeyEvent.isModifierKey(e.keyCode)) reset()
            return true
        }

        /** Sends the desktop's field what changed in the copy since last time. */
        private fun mirror() {
            val cs = getComposingSpanStart(text)
            val ce = getComposingSpanEnd(text)
            val sel = Selection.getSelectionEnd(text).coerceIn(0, text.length)
            val nb: String
            val na: String
            val np: String
            val npc: Int
            if (cs in 0..ce && ce <= text.length && ce > cs) {
                nb = text.substring(0, cs)
                np = text.substring(cs, ce)
                na = text.substring(ce)
                npc = sel.coerceIn(cs, ce) - cs
            } else {
                nb = text.substring(0, sel)
                na = text.substring(sel)
                np = ""
                npc = 0
            }
            val textChanged = nb != before || na != after
            // The composing word goes before the field's text changes (keys
            // would edit it instead), and comes back after if it's still there.
            if (preedit.isNotEmpty() && textChanged) {
                send(TEXT_PREEDIT, "")
                preedit = ""
                preeditCursor = 0
            }
            if (textChanged && selHi > selLo) {
                // The field has a selection: the first key goes to it.
                val w = before + after
                val lo = selLo.coerceIn(0, w.length)
                val hi = selHi.coerceIn(lo, w.length)
                if (nb + na == w) {
                    key(KeyEvent.KEYCODE_DPAD_LEFT) // collapses it to its start
                    before = w.substring(0, lo); after = w.substring(lo)
                } else {
                    key(KeyEvent.KEYCODE_DEL) // deletes it
                    before = w.substring(0, lo); after = w.substring(hi)
                }
                selLo = 0; selHi = 0
            }
            if (textChanged) {
                if (nb + na == before + after) {
                    // Only the cursor moved.
                    val d = points(nb) - points(before)
                    key(if (d < 0) KeyEvent.KEYCODE_DPAD_LEFT else KeyEvent.KEYCODE_DPAD_RIGHT, kotlin.math.abs(d))
                } else {
                    // What stayed the same on each side of the cursor, in whole characters.
                    var p = 0
                    while (p < before.length && p < nb.length && before[p] == nb[p]) p++
                    while (p > 0 && (splits(before, p) || splits(nb, p))) p--
                    var s = 0
                    while (s < after.length && s < na.length && after[after.length - 1 - s] == na[na.length - 1 - s]) s++
                    while (s > 0 && (splits(after, after.length - s) || splits(na, na.length - s))) s--
                    key(KeyEvent.KEYCODE_DEL, points(before, p))
                    key(KeyEvent.KEYCODE_FORWARD_DEL, points(after, 0, after.length - s))
                    type(nb.substring(p))
                    val inserted = na.substring(0, na.length - s)
                    if (inserted.isNotEmpty()) {
                        type(inserted)
                        key(KeyEvent.KEYCODE_DPAD_LEFT, points(inserted))
                    }
                }
                before = nb
                after = na
            }
            if (np != preedit || npc != preeditCursor) {
                send(TEXT_PREEDIT, np, npc)
                preedit = np
                preeditCursor = npc
            }
            // Keyboards follow the editor's cursor and composing word through this.
            updated()
        }
    }

    // KeyCharacterMap.COMBINING_ACCENT: a dead key, not a character.
    private const val KeyCharacterMapCombining = Int.MIN_VALUE
}
