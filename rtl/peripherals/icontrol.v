////////////////////////////////////////////////////////////////////////////////
//
// Filename:	icontrol.v
//
// Project:	Zip CPU -- a small, lightweight, RISC CPU soft core
//
// Purpose:	An interrupt controller, for managing many interrupt sources.
//
//	This interrupt controller started from the question of how best to
//	design a simple interrupt controller.  As such, it has a few nice
//	qualities to it:
//		1. This is wishbone compliant
//		2. It sits on a 32-bit wishbone data bus
//		3. It only consumes one address on that wishbone bus.
//		4. There is no extra delays associated with reading this
//			device.
//		5. Common operations can all be done in one clock.
//
//	So, how shall this be used?  First, the 32-bit word is broken down as
//	follows:
//
//	Bit 31	- This is the global interrupt enable bit.  If set, interrupts
//		will be generated and passed on as they come in.
//	Bits 16-30	- These are specific interrupt enable lines.  If set,
//		interrupts from source (bit#-16) will be enabled.
//		To set this line and enable interrupts from this source, write
//		to the register with this bit set and the global enable set.
//		To disable this line, write to this register with global enable
//		bit not set, but this bit set.  (Writing a zero to any of these
//		bits has no effect, either setting or unsetting them.)
//	Bit 15 - This is the any interrupt pin.  If any interrupt is pending,
//		this bit will be set.
//	Bits 0-14	- These are interrupt bits.  When set, an interrupt is
//		pending from the corresponding source--regardless of whether
//		it was enabled.  (If not enabled, it won't generate an
//		interrupt, but it will still register here.)  To clear any
//		of these bits, write a '1' to the corresponding bit.  Writing
//		a zero to any of these bits has no effect.
//
//	The peripheral also sports a parameter, IUSED, which can be set
//	to any value between 1 and (buswidth/2-1, or) 15 inclusive.  This will
//	be the number of interrupts handled by this routine.  (Without the
//	parameter, Vivado was complaining about unused bits.  With it, we can
//	keep the complaints down and still use the routine).
//
//	To get access to more than 15 interrupts, chain these together, so
//	that one interrupt controller device feeds another.
//
//
// Creator:	Dan Gisselquist, Ph.D.
//		Gisselquist Technology, LLC
//
////////////////////////////////////////////////////////////////////////////////
//
// Copyright (C) 2015,2017-2018, Gisselquist Technology, LLC
//
// This program is free software (firmware): you can redistribute it and/or
// modify it under the terms of  the GNU General Public License as published
// by the Free Software Foundation, either version 3 of the License, or (at
// your option) any later version.
//
// This program is distributed in the hope that it will be useful, but WITHOUT
// ANY WARRANTY; without even the implied warranty of MERCHANTIBILITY or
// FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
// for more details.
//
// You should have received a copy of the GNU General Public License along
// with this program.  (It's in the $(ROOT)/doc directory.  Run make with no
// target there if the PDF file isn't present.)  If not, see
// <http://www.gnu.org/licenses/> for a copy.
//
// License:	GPL, v3, as defined and found on www.gnu.org,
//		http://www.gnu.org/licenses/gpl.html
//
//
////////////////////////////////////////////////////////////////////////////////
//
//
`default_nettype	none
//
module	icontrol(i_clk, i_reset, i_wb_stb, i_wb_we, i_wb_data,
		o_wb_ack, o_wb_stall, o_wb_data,
		i_brd_ints, o_interrupt);
	parameter	IUSED = 15, BW=32;
	input	wire			i_clk, i_reset;
	input	wire			i_wb_stb, i_wb_we;
	input	wire	[BW-1:0]	i_wb_data;
	output	wire			o_wb_ack, o_wb_stall;
	output	reg	[BW-1:0]	o_wb_data;
	input	wire	[(IUSED-1):0]	i_brd_ints;
	output	wire			o_interrupt;

	reg	[(IUSED-1):0]	r_int_state;
	reg	[(IUSED-1):0]	r_int_enable;
	wire	[(IUSED-1):0]	nxt_int_state;
	reg			r_gie;
	wire			w_any;

	wire			wb_write;
	assign	wb_write = (i_wb_stb)&&(i_wb_we);

	assign	nxt_int_state = (r_int_state|i_brd_ints);

	//
	// First step: figure out which interrupts have triggered.
	// An interrupt "triggers" when the incoming interrupt wire is high,
	// and stays triggered until cleared by the bus.
	initial	r_int_state = 0;
	always @(posedge i_clk)
		if (i_reset)
			r_int_state  <= 0;
		else if (wb_write)
			r_int_state <= i_brd_ints | (r_int_state & (~i_wb_data[(IUSED-1):0]));
		else
			r_int_state <= nxt_int_state;

	//
	// Second step: determine which interrupts are enabled.
	// Only interrupts that are enabled will be propagated forward on
	// the global interrupt line.
	initial	r_int_enable = 0;
	always @(posedge i_clk)
		if (i_reset)
			r_int_enable <= 0;
		else if ((wb_write)&&(i_wb_data[BW-1]))
			r_int_enable <= r_int_enable | i_wb_data[(16+IUSED-1):16];
		else if ((wb_write)&&(!i_wb_data[BW-1]))
			r_int_enable <= r_int_enable & (~ i_wb_data[(16+IUSED-1):16]);

	//
	// Third step: The global interrupt enable bit.
	initial	r_gie = 1'b0;
	always @(posedge i_clk)
		if (i_reset)
			r_gie <= 1'b0;
		else if (wb_write)
			r_gie <= i_wb_data[BW-1];

	//
	// Have "any" enabled interrupts triggered?
	assign	w_any = ((r_int_state & r_int_enable) != 0);

	// How then shall the interrupt wire be set?
	initial	o_interrupt = 1'b0;
	always @(posedge i_clk)
	if (i_reset)
		o_interrupt <= 1'b0;
	else
		o_interrupt <= (r_gie)&&(w_any);

	//
	// Create the output data.  Place this into the next clock, to keep
	// it synchronous with w_any.
	generate
	if (IUSED < 15)
	begin
		always @(posedge i_clk)
			o_wb_data <= {
				r_gie, { {(15-IUSED){1'b0}}, r_int_enable }, 
				w_any, { {(15-IUSED){1'b0}}, r_int_state  } };
	end else begin
		always @(posedge i_clk)
			o_wb_data <= { r_gie, r_int_enable, w_any, r_int_state };
	end endgenerate

	// Make verilator happy
	// verilator lint_off UNUSED
	wire	[30:0]	unused;
	assign	unused = i_wb_data[30:0];
	// verilator lint_on  UNUSED

	assign	o_wb_ack   = i_wb_stb;
	assign	o_wb_stall = 1'b0;


////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
//
//
// Formal properties section
//
//
////////////////////////////////////////////////////////////////////////////////
////////////////////////////////////////////////////////////////////////////////
`ifdef	FORMAL
`ifdef	ICONTROL
`define	ASSUME	assume
`else
`define	ASSUME	assert
`endif

	reg	f_past_valid;

	initial	f_past_valid = 1'b0;
	always @(posedge i_clk)
		f_past_valid <= 1'b1;

	//
	//
	// Reset handling
	//
	//


	initial	`ASSUME(i_reset);
	always @(*)
	if (!f_past_valid)
		`ASSUME(i_reset);

	always @(posedge i_clk)
	if ((!f_past_valid)||($past(i_reset)))
	begin
		assert(w_any == 0);
		assert(o_interrupt == 0);
		assert(r_gie == 0);
		assert(r_int_enable == 0);
	end

	////////////////////////////////////////
	//
	// Formal contract
	//
	////////////////////////////////////////
	//
	// Make sure any enabled interrupt generates an outgoing interrupt
	// ... assuming the master interrupt enable is true and the
	// individual interrupt enable is true as well.
	always @(posedge i_clk)
	if (((f_past_valid)&&(!$past(i_reset)))
			&&($past(r_int_state) & $past(r_int_enable))
			&&($past(r_gie)) )
		assert(o_interrupt);

	//
	// If the master enable is off, then no interrupt should be asserted.
	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(r_gie)))
		assert(!o_interrupt);


	// An incoming interrupt line that is hgih should affect the interrupt
	// state line for that interrupt line on the next clock
	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(i_reset)))
		assert((r_int_state & $past(i_brd_ints))==$past(i_brd_ints));


	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(i_reset))&&($past(wb_write)))
	begin
		// Following a write, interrupts may have been cleared.
		assert(r_int_state == (($past(i_brd_ints))
			|(($past(r_int_state))&(~$past(i_wb_data[IUSED-1:0])))));
		// The global interrupt enable may also be adjusted by a write
		assert(r_gie == $past(i_wb_data[BW-1]));
	end else if ((f_past_valid)&&(!$past(i_reset)))
	begin

		// Apart from a write, the interrupt state should only ever
		// accumulate interrupts
		assert(r_int_state == ($past(r_int_state)|$past(i_brd_ints)));

		// ... and the global interrupt state should remain unchanged
		assert(r_gie == $past(r_gie));
	end

	////////////////////////////////////////
	//
	// Other consistency logic
	//
	////////////////////////////////////////
	//
	// Without a write or a reset, past interrupts should remain
	// enabled.
	always @(posedge i_clk)
	if ((f_past_valid)&&($past(w_any))
			&&(!$past(wb_write))&&(!$past(i_reset)))
		assert(w_any);

	// The outgoing interrupt should never be high unless w_any
	// is also high
	always @(posedge i_clk)
	if ((f_past_valid)&&(!$past(w_any)))
		assert(!o_interrupt);

`endif
endmodule
