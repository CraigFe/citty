open Notty
open Nottui
open Lwd.Infix

let (!$) x = Lwd.join (Lwd.get x)
let empty_lwd = Lwd.return Ui.empty

let string ?(attr=A.empty) str =
  let control_character_index str i =
    let len = String.length str in
    let i = ref i in
    while let i = !i in i < len && str.[i] >= ' ' do
      incr i;
    done;
    if !i = len then raise Not_found;
    !i
  in
  let rec split str i =
    match control_character_index str i with
    | j ->
      let img = I.string attr (String.sub str i (j - i)) in
      img :: split str (j + 1)
    | exception Not_found ->
      [I.string attr
         (if i = 0 then str
          else String.sub str i (String.length str - i))]
  in
  Ui.atom (I.vcat (split str 0))

let printf ?attr fmt =
  Printf.ksprintf (string ?attr) fmt

let fmt ?attr fmt =
  Format.kasprintf (string ?attr) fmt

let attr_menu_main = A.(bg green ++ fg black)
let attr_menu_sub = A.(bg lightgreen ++ fg black)

let menu_overlay ?dx ?dy handler t =
  let placeholder = Lwd.return (Ui.atom (I.void 1 0)) in
  let body = Lwd_utils.pack Ui.pack_x [placeholder; t; placeholder] in
  let bg = Lwd.map' body @@ fun t ->
    let {Ui. w; h; _} = Ui.layout_spec t in
    Ui.atom (I.char A.(bg lightgreen) ' ' w h)
  in
  Lwd.map (Ui.overlay ?dx ?dy ~handler) (Lwd_utils.pack Ui.pack_z [bg; body])

let scroll_step = 1

type scroll_state = {
  position: int;
  bound : int;
  visible : int;
  total : int;
}

let default_scroll_state = { position = 0; bound = 0; visible = 0; total = 0 }

let vscroll_area ~state ~change t =
  let visible = ref (-1) in
  let total = ref (-1) in
  let scroll state delta =
    let position = state.position + delta in
    let position = max 0 (min state.bound position) in
    if position <> state.position then
      change `Action {state with position};
    `Handled
  in
  let focus_handler state = {
    Ui.
    status = (fun _ _ -> ());
    action = (fun _ -> function
        (*| `Arrow `Left , _ -> scroll (-scroll_step) 0*)
        (*| `Arrow `Right, _ -> scroll (+scroll_step) 0*)
        | `Arrow `Up   , _ -> scroll state (-scroll_step)
        | `Arrow `Down , _ -> scroll state (+scroll_step)
        | _ -> `Unhandled
      );
  } in
  let scroll_handler state ~x:_ ~y:_ = function
    | `Scroll `Up   -> scroll state (-scroll_step)
    | `Scroll `Down -> scroll state (+scroll_step)
    | _ -> `Unhandled
  in
  Lwd.map2' t state @@ fun t state ->
  t
  |> Ui.scroll_area 0 state.position
  |> Ui.resize ~h:0 ~sh:1
  |> Ui.size_sensor (fun _ h ->
      let tchange =
        if !total <> (Ui.layout_spec t).Ui.h
        then (total := (Ui.layout_spec t).Ui.h; true)
        else false
      in
      let vchange =
        if !visible <> h
        then (visible := h; true)
        else false
      in
      if tchange || vchange then
        change `Content {state with visible = !visible; total = !total;
                                    bound = max 0 (!total - !visible); }
    )
  |> Ui.mouse_area (scroll_handler state)
  |> Ui.focus_area Time.origin (focus_handler state)

let scroll_area ?(offset=0,0) t =
  let offset = Lwd.var offset in
  let scroll d_x d_y =
    let s_x, s_y = Lwd.peek offset in
    let s_x = max 0 (s_x + d_x) in
    let s_y = max 0 (s_y + d_y) in
    Lwd.set offset (s_x, s_y);
    `Handled
  in
  let focus_handler = {
    Ui.
    status = (fun _ _ -> ());
    action = (fun _ -> function
        | `Arrow `Left , _ -> scroll (-scroll_step) 0
        | `Arrow `Right, _ -> scroll (+scroll_step) 0
        | `Arrow `Up   , _ -> scroll 0 (-scroll_step)
        | `Arrow `Down , _ -> scroll 0 (+scroll_step)
        | _ -> `Unhandled
      );
  } in
  let scroll_handler ~x:_ ~y:_ = function
    | `Scroll `Up   -> scroll 0 (-scroll_step)
    | `Scroll `Down -> scroll 0 (+scroll_step)
    | _ -> `Unhandled
  in
  Lwd.map2' t (Lwd.get offset) @@ fun t (s_x, s_y) ->
  t
  |> Ui.scroll_area s_x s_y
  |> Ui.mouse_area scroll_handler
  |> Ui.focus_area Time.origin focus_handler

let main_menu_item text f =
  let text = string ~attr:attr_menu_main (" " ^ text ^ " ") in
  let v = Lwd.var empty_lwd in
  let visible = ref false in
  let on_click ~x:_ ~y:_ = function
    | `Left ->
      visible := not !visible;
      if not !visible then (
        v $= Lwd.return Ui.empty
      ) else (
        let h ~x:_ ~y:_ = function
          | `Left ->
            visible := false; v $= Lwd.return Ui.empty; `Unhandled
          | _ -> `Unhandled
        in
        v $= menu_overlay h (f ())
      );
      `Handled
    | _ -> `Unhandled
  in
  Lwd_utils.pack Ui.pack_y [
    Lwd.return (Ui.mouse_area on_click text);
    Lwd.join (Lwd.get v)
  ]

let sub_menu_item text f =
  let text = string ~attr:attr_menu_sub text in
  let v = Lwd.var empty_lwd in
  let visible = ref false in
  let on_click ~x:_ ~y:_ = function
    | `Left ->
      visible := not !visible;
      if not !visible then (
        v $= Lwd.return Ui.empty
      ) else (
        let h ~x:_ ~y:_ = function
          | `Left ->
            visible := false; v $= Lwd.return Ui.empty; `Unhandled
          | _ -> `Unhandled
        in
        v $= menu_overlay h (f ())
      );
      `Handled
    | _ -> `Unhandled
  in
  Lwd_utils.pack Ui.pack_x [
    Lwd.return (Ui.mouse_area on_click text);
    Lwd.join (Lwd.get v)
  ]

let sub_entry text f =
  let text = string ~attr:attr_menu_sub text in
  let on_click ~x:_ ~y:_ = function
    | `Left -> f (); `Handled
    | _ -> `Unhandled
  in
  Ui.mouse_area on_click text

let v_pane left right =
  let w = ref 10 in
  let h = ref 10 in
  let split = ref 0.5 in
  let splitter = Lwd.var empty_lwd in
  let splitter_bg = Lwd.var Ui.empty in
  let left_bg = Lwd.var Ui.empty in
  let right_bg = Lwd.var Ui.empty in
  let left_pane = Lwd.var empty_lwd in
  let right_pane = Lwd.var empty_lwd in
  let left_content = Lwd_utils.pack Ui.pack_z [Lwd.get left_bg; left] in
  let right_content = Lwd_utils.pack Ui.pack_z [Lwd.get right_bg; right] in
  let node = Lwd_utils.pack Ui.pack_y [!$left_pane; !$splitter; !$right_pane] in
  let render () =
    let split = int_of_float (!split *. float !h) in
    let split = min (!h - 1) (max split 0) in
    left_bg $= Ui.atom
      (I.char A.(bg lightblue) ' ' !w split);
    right_bg $= Ui.atom
      (I.char A.(bg lightblue) ' ' !w (!h - split - 1));
    left_pane $= Lwd.map' left_content
      (fun t -> Ui.resize ~w:!w ~h:split t);
    right_pane $= Lwd.map' right_content
      (fun t -> Ui.resize ~w:!w ~h:(!h - split - 1) t);
    splitter_bg $= Ui.atom (I.char A.(bg lightyellow) ' ' !w 1);
  in
  let action ~x:_ ~y:_ = function
    | `Left ->
      let y0 = int_of_float (!split *. float !h) in
      `Grab ((fun ~x:_ ~y ->
          let y0' = y0 + y in
          split := min 1.0 (max 0.0 (float y0' /. float !h));
          render ()
        ), (fun ~x:_ ~y:_ -> ()))
    | _ -> `Unhandled
  in
  splitter $= Lwd.map (Ui.mouse_area action) (Lwd.get splitter_bg);
  render ();
  let on_resize ew eh =
    if !w <> ew || !h <> eh then (
      w := ew; h := eh;
      render ()
    )
  in
  Lwd.map' node @@ fun t ->
  Ui.size_sensor on_resize (Ui.resize ~w:10 ~h:10 ~sw:1 ~sh:1 t)

let h_pane top bottom =
  let w = ref 10 in
  let h = ref 10 in
  let split = ref 0.5 in
  let splitter = Lwd.var empty_lwd in
  let splitter_bg = Lwd.var Ui.empty in
  let left_bg = Lwd.var Ui.empty in
  let right_bg = Lwd.var Ui.empty in
  let left_pane = Lwd.var empty_lwd in
  let right_pane = Lwd.var empty_lwd in
  let left_content = Lwd_utils.pack Ui.pack_z [Lwd.get left_bg; top] in
  let right_content = Lwd_utils.pack Ui.pack_z [Lwd.get right_bg; bottom] in
  let node = Lwd_utils.pack Ui.pack_x [!$left_pane; !$splitter; !$right_pane] in
  let render () =
    let split = int_of_float (!split *. float !w) in
    let split = min (!w - 1) (max split 0) in
    left_bg $= Ui.atom (Notty.I.char Notty.A.(bg lightblue) ' ' split !h);
    right_bg $= Ui.atom (Notty.I.char Notty.A.(bg lightblue) ' ' (!w - split - 1) !h);
    left_pane $= Lwd.map' left_content
      (fun t -> Ui.resize ~w:split ~h:!h t);
    right_pane $= Lwd.map' right_content
      (fun t -> Ui.resize ~w:(!w - split - 1) ~h:!h t);
    splitter_bg $= Ui.atom (Notty.I.char Notty.A.(bg lightyellow) ' ' 1 !h);
  in
  let action ~x:_ ~y:_ = function
    | `Left ->
      let x0 = int_of_float (!split *. float !w) in
      `Grab ((fun ~x ~y:_ ->
          let x0' = x0 + x in
          split := min 1.0 (max 0.0 (float x0' /. float !w));
          render ()
        ), (fun ~x:_ ~y:_ -> ()))
    | _ -> `Unhandled
  in
  splitter $= Lwd.map (Ui.mouse_area action) (Lwd.get splitter_bg);
  render ();
  let on_resize ew eh =
    if !w <> ew || !h <> eh then (
      w := ew; h := eh;
      render ()
    )
  in
  Lwd.map' node @@ fun t ->
  Ui.size_sensor on_resize (Ui.resize ~w:10 ~h:10 ~sw:1 ~sh:1 t)

let sub' str p l =
  if p = 0 && l = String.length str
  then str
  else String.sub str p l

let edit_field state ~on_change ~on_submit =
  let vfocused = Lwd.var false in
  let time = ref Time.origin in
  let update focused (text, pos) =
    let pos = min (max 0 pos) (String.length text) in
    let content =
      Ui.atom @@ I.hcat @@
      if focused then (
        let attr = A.(bg lightblue) in
        let len = String.length text in
        (if pos >= len
         then [I.string attr text]
         else [I.string attr (sub' text 0 pos)])
        @
        (if pos < String.length text then
           [I.string A.(bg lightred) (sub' text pos 1);
            I.string attr (sub' text (pos + 1) (len - pos - 1))]
         else [I.string A.(bg lightred) " "]);
      ) else
        [I.string A.empty (if text = "" then " " else text)]
    in
    let handler = {
      Ui.
      action = (fun _ key -> match key with
          | `ASCII k, _ ->
            let text =
              if pos < String.length text then (
                String.sub text 0 pos ^ String.make 1 k ^
                String.sub text pos (String.length text - pos)
              ) else (
                text ^ String.make 1 k
              )
            in
            on_change (text, (pos + 1));
            `Handled
          | `Backspace, _ ->
            let text =
              if pos > 0 then (
                if pos < String.length text then (
                  String.sub text 0 (pos - 1) ^
                  String.sub text pos (String.length text - pos)
                ) else if String.length text > 0 then (
                  String.sub text 0 (String.length text - 1)
                ) else text
              ) else text
            in
            let pos = max 0 (pos - 1) in
            on_change (text, pos);
            `Handled
          | `Enter, _ -> on_submit (text, pos); `Handled
          | `Arrow `Left, _ ->
            let pos = min (String.length text) pos in
            if pos > 0 then (
              on_change (text, pos - 1);
              `Handled
            )
            else `Unhandled
          | `Arrow `Right, _ ->
            let pos = pos + 1 in
            if pos <= String.length text
            then (on_change (text, pos); `Handled)
            else `Unhandled
          | _ -> `Unhandled);
      status = (fun _ event ->
          let focused' = match event with
            | `Enter -> true
            | `Leave -> false
            | _ -> focused
          in
          if focused' <> focused then
            vfocused $= focused'
        );
    } in
    Ui.focus_area !time handler content
  in
  let node = Lwd.var (Lwd.map2 update (Lwd.get vfocused) state) in
  let mouse_grab (text, pos) ~x ~y:_ = function
    | `Left ->
      if x <> pos then on_change (text, x);
      time := Time.next ();
      node $= Lwd.map2  update (Lwd.get vfocused) state;
      `Handled
    | _ -> `Unhandled
  in
  Lwd.map2' state !$node @@ fun state content ->
  Ui.mouse_area (mouse_grab state) content

