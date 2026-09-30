package axi_mut_pkg;

  typedef enum int unsigned {
    MUT_NONE       = 0,
    MUT_VALID_DROP = 1,  // back-pressure the beat, drop VALID on obs for one cycle
    MUT_GLITCH     = 2,  // back-pressure the beat, flip payload bits on obs for one cycle
    MUT_OVERRIDE   = 3   // replace payload bits on obs for the whole beat
  } mut_op_e;

  typedef enum int unsigned { CH_AW, CH_W, CH_B, CH_AR, CH_R, CH_NONE } mut_chan_e;

  function automatic mut_op_e op_from_string(string s);
    case (s)
      "",  "NONE"  : return MUT_NONE;
      "VALID_DROP" : return MUT_VALID_DROP;
      "GLITCH"     : return MUT_GLITCH;
      "OVERRIDE"   : return MUT_OVERRIDE;
      default      : $fatal(1, "[MUT] unknown +mut_op=%s", s);
    endcase
  endfunction

  function automatic mut_chan_e chan_from_string(string s);
    case (s)
      ""  : return CH_NONE;
      "AW": return CH_AW;
      "W" : return CH_W;
      "B" : return CH_B;
      "AR": return CH_AR;
      "R" : return CH_R;
      default: $fatal(1, "[MUT] unknown +mut_chan=%s", s);
    endcase
  endfunction

endpackage
