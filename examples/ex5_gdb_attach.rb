#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 5 : gdb を使用して接続中のセッションにアタッチして
#             'user commits' 統計値が増加したときに止める
# 実行方法 : ruby ex5_gdb_attach.rb <プログラムのパス> <アタッチするプロセスの pid> <出力ファイル名>
# 実行例 : ruby ex5_gdb_attach.rb "/u01/app/oracle/product/11.2.0/dbhome_1/bin/oracle" 3687 output.txt

require '../repro'

oracle_path = ARGV[0]
spid = ARGV[1]
filename = ARGV[2]

file = filename ? File.open("#{filename.to_s}", "w") : STDOUT

ss = Repro::ScreenSession.new

# oracle プロセスの SESSION ID を取得
sys = Repro::SQLPlus.new(ss.new_window)
sys.title("sys")
sys.cmd("connect /as sysdba")
sid = sys.cmd("select sid from v$session s, v$process p where p.spid = #{spid} and s.paddr = p.addr;").slice(/^\s*[0-9]+\s*$/).strip

gdb = Repro::GDB.new(ss.new_window)
gdb.title("gdb")

# oracle プロセスへのアタッチ
gdb.cmd("file #{oracle_path}")
gdb.cmd("exec-file #{oracle_path}")
gdb.cmd("attach #{spid}")

stack = gdb.cmd("bt").each_line.map { |line| line.slice(/\S+ \(\)/) }
last_stack = stack
func = stack[0]
last_func = func
stack.reverse.each_with_index do |f, i|
  if i == 0
    file.puts f
  else
    file.puts "  " * i + "-> #{f}"
  end
end

file.puts "Start at #{Time.now.to_s}"

Signal.trap(:INT) do
  ss.detach
  file.close
end

file.sync = true

value0 = sys.cmd("select value from v$sesstat where sid = #{sid} and statistic# = (select statistic# from v$statname where name = 'user commits');").slice(/[0-9]+\n$/).strip
value = value0
# 'user commits' 統計値が増加した時にループを抜ける
until value && value.to_i > value0.to_i
  # 次の関数に辿り着くまで stepi 実行
  func = gdb.cmd("si").slice(/\w+ \(\)/) while func == last_func

  # /lib64 配下の関数はスキップする
  if gdb.cmd("si") =~ /from \/lib64/
    gdb.cmd("finish")
    next
  end

  stack = gdb.cmd("bt").each_line.map { |line| line.slice(/\S+ \(\)/) }
  stack.delete("?? ()")

  if stack.size > last_stack.size
    file.puts "  " * (stack.size - 1) + "-> #{stack[0]}"
  elsif stack.size < last_stack.size
    file.puts "  " * (last_stack.size - 1) + "<- #{last_stack[0]}"
  end

  last_func = func
  last_stack = stack

  unless value.nil?
    value = sys.cmd("select value from v$sesstat where sid = #{sid} and statistic# = (select statistic# from v$statname where name = 'user commits');", 1)
    value = value.slice(/[0-9]+\n$/).strip unless value.nil?
  else
    value = sys.wait_prompt(1)
  end
end

gdb.cmd("bt")

ss.detach
file.close
