(* stat(1) built with liburing. *)

module S = Uring.Statx

(* TODO move into Uring.Statx? *)
let pp_time f t =
  let nsec, sec = modf t in
  let tm = Unix.localtime sec in
  Format.fprintf f "%04d-%02d-%02d %02d:%02d:%02d.%9.0f +0000"
    (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday
    tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec
    (nsec *. 1e9)
  
let get_completion_and_print uring =
  let (fname, buf), _ =
    match Uring.wait uring with
    | Some { data; result } -> (data, result)
    | None -> failwith "retry"
  in
  let kind = S.kind buf in
  let opt_symlink = match kind with
      `Symbolic_link -> Printf.sprintf " -> %s" (Unix.readlink fname) (* TODO no readlink in io_uring? *)
    | _ -> "" in
  Format.printf "  File: %s%s\n  Size: %Lu\t\tBlocks: %Lu\tIO Block: %Lu\t %a\nDevice: %Lu\tInode: %Lu\tLinks: %Lu\nAccess: (%04o/TODO)\tUid: (%Lu/TODO)\tGid: (%Lu/TODO)\nAccess: %a\nModify: %a\nChange: %a\n Birth: %a\n%!"
    fname opt_symlink
    (Optint.Int63.to_int64 (S.size buf))
    (S.blocks buf)
    (S.blksize buf)
    S.pp_kind (S.kind buf)
    (S.dev buf) (* TODO expose makedev/major/minor *) (S.ino buf) (S.nlink buf)
    (S.perm buf) (S.uid buf) (S.gid buf)
    pp_time (S.atime buf)
    pp_time (S.mtime buf)
    pp_time (S.ctime buf)
    pp_time (S.btime buf)

let submit_stat_request fname buf uring =
  let mask = S.Mask.(basic_stats + btime) in
  let flags = S.Flags.(symlink_nofollow + statx_dont_sync) in
  let _ = Uring.statx uring ~mask fname buf flags (fname,buf) in
  let numreq = Uring.submit uring in
  assert(numreq=1);
  ()

let () =
   let fname = Sys.argv.(1) in
   let buf = S.create () in
   let uring = Uring.create ~queue_depth:1 () in
   submit_stat_request fname buf uring;
   get_completion_and_print uring