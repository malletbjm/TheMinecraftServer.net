using System;
using System.Drawing;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace Launcher
{
    internal sealed class MainForm : Form
    {
        private readonly RichTextBox _output;
        private readonly Timer _caretTimer;
        private Action? _continueHandler;
        private bool _awaitingContinue;
        private bool _allowClose = true;
        private Action? _closeHandler;
        private int _statusStart = -1;
        private int _statusLength = 0;
        private const float MinFontSize = 6f;

        public int Columns { get; private set; }
        public int Rows { get; private set; }

        public MainForm(Icon? appIcon, int columns, int rows)
        {
            Columns = columns;
            Rows = rows;

            Text = "TheMinecraftServer.net Mods Installer";
            StartPosition = FormStartPosition.CenterScreen;
            FormBorderStyle = FormBorderStyle.FixedSingle;
            MaximizeBox = false;
            MinimizeBox = true;
            BackColor = Color.Black;
            KeyPreview = true;
            AutoScaleMode = AutoScaleMode.None;

            if (appIcon != null)
            {
                Icon = appIcon;
            }

            _output = new RichTextBox
            {
                Dock = DockStyle.Fill,
                ReadOnly = true,
                BorderStyle = BorderStyle.None,
                BackColor = Color.Black,
                ForeColor = Color.White,
                Font = new Font("Consolas", 10f, FontStyle.Regular, GraphicsUnit.Point),
                HideSelection = false,
                ScrollBars = RichTextBoxScrollBars.None,
                WordWrap = false,
                Margin = new Padding(0),
                TabStop = false,
                ShortcutsEnabled = false,
                Cursor = Cursors.Arrow
            };
            _output.GotFocus += (_, _) => HideCaretSafe(_output);
            _output.SelectionChanged += (_, _) => HideCaretSafe(_output);
            _output.MouseDown += (_, _) => HideCaretSafe(_output);

            Controls.Add(_output);

            _caretTimer = new Timer { Interval = 250 };
            _caretTimer.Tick += (_, _) => HideCaretSafe(_output);
            _caretTimer.Start();

            ApplySize(columns, rows);
        }

        public void AllowClose(bool allow)
        {
            _allowClose = allow;
        }

        public void SetCloseHandler(Action? handler)
        {
            _closeHandler = handler;
        }

        protected override void OnFormClosing(FormClosingEventArgs e)
        {
            try
            {
                _closeHandler?.Invoke();
            }
            catch
            {
            }

            if (!_allowClose)
            {
                e.Cancel = true;
                return;
            }

            _caretTimer.Stop();
            base.OnFormClosing(e);
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            TrySetDarkTitleBar();
        }

        public void AppendText(string text, Color foreground, Color background, bool newLine)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => AppendText(text, foreground, background, newLine)));
                return;
            }

            _output.SelectionStart = _output.TextLength;
            _output.SelectionLength = 0;
            _output.SelectionColor = foreground;
            _output.SelectionBackColor = background;
            _output.SelectionAlignment = HorizontalAlignment.Left;
            _output.AppendText(newLine ? text + Environment.NewLine : text);
            _output.SelectionColor = _output.ForeColor;
            _output.SelectionBackColor = _output.BackColor;
            _output.ScrollToCaret();
            HideCaretSafe(_output);
        }

        public void AppendLine(string line, Color foreground, Color background, bool center)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => AppendLine(line, foreground, background, center)));
                return;
            }

            _output.SelectionStart = _output.TextLength;
            _output.SelectionLength = 0;
            _output.SelectionColor = foreground;
            _output.SelectionBackColor = background;
            _output.SelectionAlignment = center ? HorizontalAlignment.Center : HorizontalAlignment.Left;
            _output.AppendText((line ?? string.Empty) + Environment.NewLine);
            _output.SelectionColor = _output.ForeColor;
            _output.SelectionBackColor = _output.BackColor;
            _output.ScrollToCaret();
            HideCaretSafe(_output);
        }

        public void ClearOutput()
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(ClearOutput));
                return;
            }

            _output.Clear();
            _statusStart = -1;
            _statusLength = 0;
        }

        public void SetStatusLine(string line, Color foreground, Color background, bool center)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => SetStatusLine(line, foreground, background, center)));
                return;
            }

            int end = _output.TextLength;
            if (_statusStart < 0 || _statusStart + _statusLength < end)
            {
                _statusStart = end;
                _statusLength = 0;
            }

            _output.SelectionStart = _statusStart;
            _output.SelectionLength = _statusLength;
            _output.SelectionColor = foreground;
            _output.SelectionBackColor = background;
            _output.SelectionAlignment = center ? HorizontalAlignment.Center : HorizontalAlignment.Left;
            _output.SelectedText = (line ?? string.Empty) + Environment.NewLine;
            _statusLength = (line ?? string.Empty).Length + Environment.NewLine.Length;
            _output.SelectionColor = _output.ForeColor;
            _output.SelectionBackColor = _output.BackColor;
            _output.ScrollToCaret();
            HideCaretSafe(_output);
        }

        public void SetWindowTitle(string title)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => SetWindowTitle(title)));
                return;
            }

            Text = title;
        }

        public void ApplySize(int columns, int rows)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => ApplySize(columns, rows)));
                return;
            }

            Columns = columns;
            Rows = rows;

            float fontSize = GetFittingFontSize(columns, rows);
            if (Math.Abs(_output.Font.Size - fontSize) > 0.1f)
            {
                _output.Font = new Font("Consolas", fontSize, FontStyle.Regular, GraphicsUnit.Point);
            }

            string probe = new string('W', Math.Max(1, columns));
            Size textSize = TextRenderer.MeasureText(probe, _output.Font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
            int charWidth = Math.Max(1, textSize.Width / Math.Max(1, columns));
            int lineHeight = Math.Max(TextRenderer.MeasureText("W", _output.Font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Height, 1);
            int width = Math.Max(200, charWidth * columns);
            int height = Math.Max(120, lineHeight * rows);
            ClientSize = new Size(width, height);
            MinimumSize = Size;
            MaximumSize = Size;

            CenterIfReady();
            HideCaretSafe(_output);
        }

        public void SetContinueHandler(Action? handler)
        {
            _continueHandler = handler;
        }

        public void ShowContinue(string? promptText = null)
        {
            if (InvokeRequired)
            {
                BeginInvoke(new Action(() => ShowContinue(promptText)));
                return;
            }

            _awaitingContinue = true;
        }

        protected override bool ProcessCmdKey(ref Message msg, Keys keyData)
        {
            if (_awaitingContinue && keyData == Keys.Enter)
            {
                TriggerContinue();
                return true;
            }

            return base.ProcessCmdKey(ref msg, keyData);
        }

        protected override void OnShown(EventArgs e)
        {
            base.OnShown(e);
            CenterToScreen();
        }

        private void TriggerContinue()
        {
            _awaitingContinue = false;
            _continueHandler?.Invoke();
            HideCaretSafe(_output);
        }

        private float GetFittingFontSize(int columns, int rows)
        {
            Screen screen = Screen.FromControl(this);
            int maxWidth = Math.Max(200, screen.WorkingArea.Width - 20);
            int maxHeight = Math.Max(120, screen.WorkingArea.Height - 20);

            for (float size = 10f; size >= MinFontSize; size -= 0.5f)
            {
                using Font font = new Font("Consolas", size, FontStyle.Regular, GraphicsUnit.Point);
                Size textSize = TextRenderer.MeasureText(new string('W', Math.Max(1, columns)), font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding);
                int charWidth = Math.Max(1, textSize.Width / Math.Max(1, columns));
                int lineHeight = Math.Max(TextRenderer.MeasureText("W", font, new Size(int.MaxValue, int.MaxValue), TextFormatFlags.NoPadding).Height, 1);
                int width = charWidth * columns;
                int height = lineHeight * rows;
                if (width <= maxWidth && height <= maxHeight)
                {
                    return size;
                }
            }

            return MinFontSize;
        }

        [System.Runtime.InteropServices.DllImport("user32.dll")]
        private static extern bool HideCaret(IntPtr hWnd);

        private static void HideCaretSafe(Control control)
        {
            if (control.IsHandleCreated)
            {
                HideCaret(control.Handle);
            }
        }

        private void CenterIfReady()
        {
            if (IsHandleCreated)
            {
                CenterToScreen();
            }
        }

        [DllImport("dwmapi.dll", CharSet = CharSet.Unicode, PreserveSig = true)]
        private static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int attrValue, int attrSize);

        private void TrySetDarkTitleBar()
        {
            try
            {
                int useDark = 1;
                _ = DwmSetWindowAttribute(Handle, 20, ref useDark, sizeof(int));
                _ = DwmSetWindowAttribute(Handle, 19, ref useDark, sizeof(int));
            }
            catch
            {
            }
        }
    }
}
