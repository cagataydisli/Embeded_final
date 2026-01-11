module MUX#(parameter byte_size=1)( #1 byte = 8 bit
	input [7:0]IN[byte_size-1],
	input [$clog(byte_size):0]Select,
	output [7:0]OUT
	);
	assign OUT = IN[Select];
endmodule