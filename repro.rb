# -*- coding: utf-8 -*-
require 'pty'
require 'expect'
require 'timeout'

# == Tips
#
# * screen のセッションをまとめて削除する方法
#
#   $ screen -ls | grep repro | awk '{print "screen -S "$1" -X quit"}' | sh -x
#
# * gdb でアタッチしようとすると "ptrace: Operation not permitted." となり
#   アタッチできない場合, gdb に setuid を付けてしまうと回避できる
#
#   #  ls -l /usr/bin/gdb
#   -rwxr-xr-x 1 root root 4187648 Jun 21  2011 /usr/bin/gdb
#   # chmod u+s /usr/bin/gdb  # root ユーザで実行
#   # ls -l /usr/bin/gdb
#   -rwsr-xr-x 1 root root 4187648 Jun 21  2011 /usr/bin/gdb
#
#   使用後は元に戻すこと
#   # chmod u-s /usr/bin/gdb  # root ユーザで実行
module Repro
  HOME = File.dirname(__FILE__)
  DEFAULT_SCREENRC = HOME + '/screenrc'

  module Login
    def ssh(hostname, password, user = nil, port = nil)
      command = "ssh -o StrictHostKeyChecking=no #{"-p " + port.to_s if port} #{user + '@' if user}#{hostname}"
      login_prompt = /password: /
      return login(command, login_prompt, password)
    end

    def su(user, password)
      command = "LANG=C su - #{user}"
      login_prompt = /Password: /
      return login(command, login_prompt, password)
    end

    private
    def login(command, login_prompt, password)
      current_prompt = self.prompt
      self.prompt = login_prompt
      cmd(command)
      self.prompt = current_prompt
      cmd(password)
      return self
    end
  end

  class ScreenSession
    def initialize
      @name = "repro#{Time.now.strftime("%Y%m%d%H%M%S")}"

      screen_command = "screen -S #{@name}"

      if File.exists?(DEFAULT_SCREENRC)
        screen_command += " -c #{DEFAULT_SCREENRC}"
      end

      @read, @write, @pid = PTY.spawn(screen_command)
      @write.sync = true
      $expect_verbose = true
      @read.expect(ScreenWindow::DEFAULT_PROMPT)

      @escape = screenrc_escape || "\C-a"

      screen_cmd('msgwait 0') # 現在の window を開こうとしたときの "This IS window X" というエラーを抑制

      @windows = [ScreenWindow.new(self, 0)]
      @current_window = @windows[0]
    end

    def cmd(window_number, command, timeout = 9999999)
      window = select(window_number)

      @write.print command.to_s + "\n"
      ary = @read.expect(window.prompt, timeout)
      if ary
        return remove_cmd_prompt(remove_escape_sequence(ary[0]))
      else
        return nil
      end
    end

    def screen_cmd(screen_command, read = true)
      @write.print @escape + ": #{screen_command.to_s} \n"
      if read
        begin
          timeout(0.1) { @read.read } # コマンド実行後の出力全体(select で window 切替え後の画面全体など)を読込み. 0.1秒以内に読込むと想定.
        rescue Timeout::Error
        end
      end
    end

    def new_window
      window_number = @windows.index(nil) || @windows.size

      screen_cmd('screen')

      ret = ScreenWindow.new(self, window_number)
      @windows[window_number] = ret
      @current_window = ret
      return ret
    end

    def select(window_number)
      return @current_window if @current_window.number == window_number
      raise 'Invalid window number' if @windows[window_number].nil?

      @current_window = @windows[window_number]
      screen_cmd("select #{@current_window.number}")

      return @current_window
    end

    def kill(window_number)
      return if window_number == 0

      select(window_number)
      screen_cmd('kill')
      @windows[window_number] = nil
      select(0)
    end

    def title(window_number, window_title)
      select(window_number)

      screen_cmd("title \"#{window_title}\"")
    end

    def detach
      screen_cmd('detach', false)
    end

    def quit
      screen_cmd('quit', false)
    end

    private
    def screenrc_escape
      screenrc = File.exist?(DEFAULT_SCREENRC) ?
                 DEFAULT_SCREENRC : ENV['HOME'] + '/.screenrc'
      ret = nil

      return ret unless File.exist?(screenrc)

      File.open(screenrc) do |f|
        f.each_line do |line|
          if line =~ /escape\s+(.)/
            ret = $1
          end
        end
      end

      return ret
    end

    def remove_escape_sequence(str)
      # 'ESC[1;2r', 'ESC[3;4H', 'ESC[5C' のような制御文字/エスケープシーケンスを除去する.
      # 参考 http://vt100.net/docs/vt100-ug/chapter3.html
      return str.gsub(/\e\[(\d+;)*\d+[mrBCH]/, '').gsub(/\r$/, '')
    end

    def remove_cmd_prompt(str)
      ret_ary = str.each_line.to_a
      ret_ary.shift # 1行目の入力文字列を取り除く
      ret_ary.pop   # 最後のプロンプトを取り除く
      return ret_ary.join.sub(/\n\z/, '')
    end
  end

  class ScreenWindow
    include Login

    DEFAULT_PROMPT = /[$%#>:] \z/n

    attr_reader :number
    attr_accessor :prompt

    def initialize(screen_session, number)
      @screen_session = screen_session
      @number = number
      @prompt = DEFAULT_PROMPT
    end

    def cmd(command, timeout = 9999999)
      return @screen_session.cmd(@number, command, timeout)
    end

    def title(window_title)
      @screen_session.title(@number, window_title)
    end

    def kill
      @screen_session.kill(@number)
    end
  end

  class InteractiveProgram
    def initialize(screen_window, program, prompt)
      @screen_window = screen_window
      @screen_window.prompt = prompt
      cmd(program)
    end

    def cmd(command, timeout = 9999999)
      return @screen_window.cmd(command, timeout)
    end

    def cmd_no_wait(command)
      cmd(command, 0)
    end

    def wait_prompt(timeout = 9999999)
      cmd('', timeout)
    end

    def title(window_title)
      @screen_window.title(window_title)
    end

    def close
      @screen_window.kill
    end
  end

  class Shell < InteractiveProgram
    PROGRAM = '/bin/sh'
    PROMPT  = /\$ \z/

    def initialize(screen_window)
      super(screen_window, PROGRAM, PROMPT)
    end
  end

  class SQLPlus < InteractiveProgram
    PROGRAM = 'sqlplus /nolog'
    PROMPT  = /^SQL> /

    attr_reader :pid

    def initialize(screen_window)
      super(screen_window, PROGRAM, PROMPT)
      @pid = cmd('host ps -f | grep sqlplus | grep -v grep | awk \'{print $2}\'').slice(/^[0-9]+$/)
      cmd('set tab off')
    end

    def close
      cmd_no_wait("quit")
      super
    end
  end

  class GDB < InteractiveProgram
    PROGRAM      = 'gdb'
    PROMPT       = /^\(gdb\) /

    def initialize(screen_window)
      super(screen_window, PROGRAM, PROMPT)
      cmd('set height 0')
    end

    def wait_prompt(timeout = 9999999)
      cmd('#', timeout) # gdb の場合はコメント '#' で空コマンドとなる.(空文字だと直前の命令を実行してしまう)
    end
  end
end
