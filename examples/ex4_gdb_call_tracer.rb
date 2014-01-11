#!/usr/bin/ruby
# -*- coding: utf-8 -*-
# Example 4 : Call Tracer
# 実行方法 : ruby ex4_gdb_call_tracer.rb <プログラムのパス> <アタッチするプロセスの pid> <出力ファイル名>
# 実行例 : ruby ex4_gdb_call_tracer.rb "/u01/app/oracle/product/11.2.0/dbhome_1/bin/oracle" 3687 output.txt

require '../repro'

oracle_path = ARGV[0]
spid = ARGV[1]
filename = ARGV[2]

file = filename ? File.open("#{filename.to_s}", "w") : STDOUT

ss = Repro::ScreenSession.new

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

while true
  # 次の関数に辿り着くまで stepi 実行
  func = gdb.cmd("si").slice(/\w+ \(\)/) while func == last_func

  arg = Array.new
  arg << gdb.cmd("p/x $rdi").slice(/0x[0-9a-fA-F]+$/)
  arg << gdb.cmd("p/x $rsi").slice(/0x[0-9a-fA-F]+$/)
  arg << gdb.cmd("p/x $rdx").slice(/0x[0-9a-fA-F]+$/)
  arg << gdb.cmd("p/x $rcx").slice(/0x[0-9a-fA-F]+$/)
  arg << gdb.cmd("p/x $r8").slice(/0x[0-9a-fA-F]+$/)
  arg << gdb.cmd("p/x $r9").slice(/0x[0-9a-fA-F]+$/)

  ret = gdb.cmd("p/x $rax").slice(/0x[0-9a-fA-F]+$/)

  # /lib64 配下の関数はスキップする.
  if gdb.cmd("si") =~ /from \/lib64/
    gdb.cmd("finish")
    next
  end

  stack = gdb.cmd("bt").each_line.map { |line| line.slice(/\S+ \(\)/) }
  stack.delete("?? ()")

  if stack.size > last_stack.size
    file.puts "  " * (stack.size - 1) + "-> #{stack[0]} arg:[#{arg.join(", ")}]"
  elsif stack.size < last_stack.size
    file.puts "  " * (last_stack.size - 1) + "<- #{last_stack[0]} ret:[#{ret}]"
  end

  last_func = func
  last_stack = stack
end

ss.quit
file.close
