using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Globalization;
using System.Management.Automation;
using System.Management.Automation.Host;
using System.Security;
using DrawingColor = System.Drawing.Color;
using HostBufferCell = System.Management.Automation.Host.BufferCell;
using HostCoordinates = System.Management.Automation.Host.Coordinates;
using HostKeyInfo = System.Management.Automation.Host.KeyInfo;
using HostRectangle = System.Management.Automation.Host.Rectangle;
using HostSize = System.Management.Automation.Host.Size;

namespace Launcher
{
    internal sealed class InstallerHost : PSHost
    {
        private readonly Guid _instanceId = Guid.NewGuid();
        private readonly InstallerHostUserInterface _ui;

        public InstallerHost(MainForm form, int columns, int rows)
        {
            _ui = new InstallerHostUserInterface(form, columns, rows);
        }

        public override CultureInfo CurrentCulture => CultureInfo.CurrentCulture;
        public override CultureInfo CurrentUICulture => CultureInfo.CurrentUICulture;
        public override Guid InstanceId => _instanceId;
        public override string Name => "TmsInstallerHost";
        public override PSHostUserInterface UI => _ui;
        public override Version Version => new Version(1, 0);

        public override void EnterNestedPrompt()
        {
        }

        public override void ExitNestedPrompt()
        {
        }

        public override void NotifyBeginApplication()
        {
        }

        public override void NotifyEndApplication()
        {
        }

        public override void SetShouldExit(int exitCode)
        {
            _ui.SetExitCode(exitCode);
        }
    }

    internal sealed class InstallerHostUserInterface : PSHostUserInterface
    {
        private readonly MainForm _form;
        private readonly InstallerRawUserInterface _rawUi;

        public InstallerHostUserInterface(MainForm form, int columns, int rows)
        {
            _form = form;
            _rawUi = new InstallerRawUserInterface(form, columns, rows);
        }

        public int ExitCode { get; private set; }

        public void SetExitCode(int exitCode)
        {
            ExitCode = exitCode;
        }

        public override PSHostRawUserInterface RawUI => _rawUi;

        public override void Write(string value)
        {
            Write(ConsoleColor.White, ConsoleColor.Black, value);
        }

        public override void Write(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
        {
            _form.AppendText(value, ToColor(foregroundColor), ToColor(backgroundColor), false);
        }

        public override void WriteLine(string value)
        {
            Write(ConsoleColor.White, ConsoleColor.Black, value + Environment.NewLine);
        }

        public override void WriteLine(ConsoleColor foregroundColor, ConsoleColor backgroundColor, string value)
        {
            _form.AppendText(value, ToColor(foregroundColor), ToColor(backgroundColor), true);
        }

        public override void WriteErrorLine(string value)
        {
            WriteLine(ConsoleColor.Red, ConsoleColor.Black, value);
        }

        public override void WriteDebugLine(string message)
        {
            WriteLine(ConsoleColor.DarkGray, ConsoleColor.Black, message);
        }

        public override void WriteProgress(long sourceId, ProgressRecord record)
        {
        }

        public override void WriteVerboseLine(string message)
        {
            WriteLine(ConsoleColor.Gray, ConsoleColor.Black, message);
        }

        public override void WriteWarningLine(string message)
        {
            WriteLine(ConsoleColor.Yellow, ConsoleColor.Black, message);
        }

        public override Dictionary<string, PSObject> Prompt(string caption, string message, Collection<FieldDescription> descriptions)
        {
            if (!string.IsNullOrWhiteSpace(caption))
            {
                WriteLine(ConsoleColor.White, ConsoleColor.Black, caption);
            }

            if (!string.IsNullOrWhiteSpace(message))
            {
                WriteLine(ConsoleColor.White, ConsoleColor.Black, message);
            }

            var results = new Dictionary<string, PSObject>();
            foreach (FieldDescription field in descriptions)
            {
                Write(ConsoleColor.White, ConsoleColor.Black, field.Name + ": ");
                string input = ReadLine();
                results[field.Name] = PSObject.AsPSObject(input);
            }

            return results;
        }

        public override int PromptForChoice(string caption, string message, Collection<ChoiceDescription> choices, int defaultChoice)
        {
            if (!string.IsNullOrWhiteSpace(caption))
            {
                WriteLine(ConsoleColor.White, ConsoleColor.Black, caption);
            }

            if (!string.IsNullOrWhiteSpace(message))
            {
                WriteLine(ConsoleColor.White, ConsoleColor.Black, message);
            }

            for (int i = 0; i < choices.Count; i++)
            {
                WriteLine(ConsoleColor.White, ConsoleColor.Black, $"[{i}] {choices[i].Label}");
            }

            Write(ConsoleColor.White, ConsoleColor.Black, "Choice: ");
            string input = ReadLine();
            if (int.TryParse(input, out int choice) && choice >= 0 && choice < choices.Count)
            {
                return choice;
            }

            return defaultChoice;
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName)
        {
            WriteLine(ConsoleColor.White, ConsoleColor.Black, caption);
            WriteLine(ConsoleColor.White, ConsoleColor.Black, message);
            Write(ConsoleColor.White, ConsoleColor.Black, "User: ");
            string user = string.IsNullOrWhiteSpace(userName) ? ReadLine() : userName;
            Write(ConsoleColor.White, ConsoleColor.Black, "Password: ");
            SecureString password = ReadLineAsSecureString();
            return new PSCredential(user, password);
        }

        public override PSCredential PromptForCredential(string caption, string message, string userName, string targetName,
            PSCredentialTypes allowedCredentialTypes, PSCredentialUIOptions options)
        {
            return PromptForCredential(caption, message, userName, targetName);
        }

        public override string ReadLine()
        {
            return _form.ReadLine();
        }

        public override SecureString ReadLineAsSecureString()
        {
            string input = _form.ReadLine();
            var secure = new SecureString();
            foreach (char c in input)
            {
                secure.AppendChar(c);
            }
            secure.MakeReadOnly();
            return secure;
        }

        private static DrawingColor ToColor(ConsoleColor color)
        {
            return color switch
            {
                ConsoleColor.Black => DrawingColor.Black,
                ConsoleColor.DarkBlue => DrawingColor.FromArgb(0, 0, 139),
                ConsoleColor.DarkGreen => DrawingColor.FromArgb(0, 100, 0),
                ConsoleColor.DarkCyan => DrawingColor.FromArgb(0, 139, 139),
                ConsoleColor.DarkRed => DrawingColor.FromArgb(139, 0, 0),
                ConsoleColor.DarkMagenta => DrawingColor.FromArgb(139, 0, 139),
                ConsoleColor.DarkYellow => DrawingColor.FromArgb(184, 134, 11),
                ConsoleColor.Gray => DrawingColor.FromArgb(192, 192, 192),
                ConsoleColor.DarkGray => DrawingColor.FromArgb(128, 128, 128),
                ConsoleColor.Blue => DrawingColor.FromArgb(0, 0, 255),
                ConsoleColor.Green => DrawingColor.FromArgb(0, 255, 0),
                ConsoleColor.Cyan => DrawingColor.FromArgb(0, 255, 255),
                ConsoleColor.Red => DrawingColor.FromArgb(255, 0, 0),
                ConsoleColor.Magenta => DrawingColor.FromArgb(255, 0, 255),
                ConsoleColor.Yellow => DrawingColor.FromArgb(255, 255, 0),
                ConsoleColor.White => DrawingColor.White,
                _ => DrawingColor.White
            };
        }
    }

    internal sealed class InstallerRawUserInterface : PSHostRawUserInterface
    {
        private readonly MainForm _form;
        private readonly int _fixedColumns;
        private readonly int _fixedRows;
        private HostSize _bufferSize;
        private HostSize _windowSize;
        private ConsoleColor _foreground = ConsoleColor.White;
        private ConsoleColor _background = ConsoleColor.Black;
        private HostCoordinates _cursorPosition;
        private int _cursorSize = 25;
        private string _title = string.Empty;

        public InstallerRawUserInterface(MainForm form, int columns, int rows)
        {
            _form = form;
            _fixedColumns = columns;
            _fixedRows = rows;
            _bufferSize = new HostSize(columns, rows);
            _windowSize = new HostSize(columns, rows);
        }

        public override ConsoleColor BackgroundColor
        {
            get => _background;
            set => _background = value;
        }

        public override HostSize BufferSize
        {
            get => _bufferSize;
            set => _bufferSize = new HostSize(_fixedColumns, _fixedRows);
        }

        public override HostCoordinates CursorPosition
        {
            get => _cursorPosition;
            set => _cursorPosition = value;
        }

        public override int CursorSize
        {
            get => _cursorSize;
            set => _cursorSize = value;
        }

        public override ConsoleColor ForegroundColor
        {
            get => _foreground;
            set => _foreground = value;
        }

        public override bool KeyAvailable => false;

        public override HostSize MaxPhysicalWindowSize => new HostSize(_fixedColumns, _fixedRows);

        public override HostSize MaxWindowSize => new HostSize(_fixedColumns, _fixedRows);

        public override HostCoordinates WindowPosition { get; set; }

        public override HostSize WindowSize
        {
            get => _windowSize;
            set
            {
                _windowSize = new HostSize(_fixedColumns, _fixedRows);
            }
        }

        public override string WindowTitle
        {
            get => _title;
            set
            {
                _title = value;
                _form.SetWindowTitle(value);
            }
        }

        public override void FlushInputBuffer()
        {
        }

        public override HostBufferCell[,] GetBufferContents(HostRectangle rectangle)
        {
            return new HostBufferCell[0, 0];
        }

        public override HostKeyInfo ReadKey(ReadKeyOptions options)
        {
            return new HostKeyInfo();
        }

        public override void SetBufferContents(HostCoordinates origin, HostBufferCell[,] contents)
        {
            _form.ClearOutput();
        }

        public override void SetBufferContents(HostRectangle rectangle, HostBufferCell fill)
        {
            _form.ClearOutput();
        }

        public override void ScrollBufferContents(HostRectangle source, HostCoordinates destination, HostRectangle clip, HostBufferCell fill)
        {
        }
    }
}
