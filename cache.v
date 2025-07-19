// Cache 32KB, block size 8 byte,
// coi như là RAM sẽ có hết dữ liệu và không có page fault

`define TAG 31:13             // 19 bit positon of tag on address received from cpu
`define SET 12:3              // 10 bit pos of set (index)
`define OFFSET 2:0       // 3 bit pos of byte offset 

module data_cache
// parameters
#(
    parameter SIZE = 1024*8*32, // 32 KB
    parameter NUM_WAYS = 4,
    parameter NUM_SETS = 1024,
    parameter BLOCK_SIZE = 64, // 8 bytes
    parameter WIDTH = 32, // width of a word, of data, address from cpu
    parameter MEM_WIDTH = 64, // load 8 byte dữ liệu từ RAM
    
    // address
    parameter SET_WIDTH = 10,
    parameter TAG_WIDTH = 19,
    parameter OFFSET_WIDTH = 3,

    // dùng 1 bit để chọn word
    parameter WORD1 = 3,
    parameter WORD2 = 7
)
// i/o
(
   input wire clock,
   input wire [WIDTH-1:0] address,                   // address from cpu
   input wire [WIDTH-1:0] cpu_data,                   // dữ liệu cpu muốn ghi là 32 bit
   input wire read_en,                                     // read enable signal from cpu, 1 -> read
   input wire write_en,                                    // write enable signal from cpu,  1 -> write 
   output wire hit_miss,                            // 1 nếu hit, 0 nếu miss
   output wire [WIDTH-1:0] data_ca2cpu,        // dữ liệu từ cache tới cpu
   output wire [MEM_WIDTH-1:0] data_ca2mem,         // dữ liệu từ cache tới mem (write back)
   output wire [WIDTH-1:0] addr2read_mem,          // cache miss,dựa vào địa chỉ để lấy block từ RAM
   output wire mem_rden,                              // 0 nếu như đọc từ bộ nhớ
   output wire [WIDTH-1:0] addr2write_mem,         // địa chỉ để bộ nhớ biết mà ghi vào
   output wire mem_wren,                              // 1 nếu như ghi từ bộ nhớ
   input wire [MEM_WIDTH-1:0] mem_data                  // dữ liệu từ bộ nhớ
);

// Global Parameters and Initializations
//
//
// WAY 1:
reg valid1 [0:NUM_SETS-1]; // kiểu mảng valid tương ứng với số set ở way đó
reg dirty1 [0:NUM_SETS-1];
reg [1:0] lru1 [0:NUM_SETS-1];
reg [TAG_WIDTH-1:0] tag1 [0:NUM_SETS-1];
reg [BLOCK_SIZE-1:0] data1 [0:NUM_SETS-1];

// WAY 2:
reg valid2 [0:NUM_SETS-1]; // kiểu mảng valid tương ứng với số set ở way đó
reg dirty2 [0:NUM_SETS-1];
reg [1:0] lru2 [0:NUM_SETS-1];
reg [TAG_WIDTH-1:0] tag2 [0:NUM_SETS-1];
reg [BLOCK_SIZE-1:0] data2 [0:NUM_SETS-1];

// WAY 3:
reg valid3 [0:NUM_SETS-1]; // kiểu mảng valid tương ứng với số set ở way đó
reg dirty3 [0:NUM_SETS-1];
reg [1:0] lru3 [0:NUM_SETS-1];
reg [TAG_WIDTH-1:0] tag3 [0:NUM_SETS-1];
reg [BLOCK_SIZE-1:0] data3 [0:NUM_SETS-1];

// WAY 4:   
reg valid4 [0:NUM_SETS-1]; // kiểu mảng valid tương ứng với số set ở way đó
reg dirty4 [0:NUM_SETS-1];
reg [1:0] lru4 [0:NUM_SETS-1];
reg [TAG_WIDTH-1:0] tag4 [0:NUM_SETS-1];
reg [BLOCK_SIZE-1:0] data4 [0:NUM_SETS-1];

integer k;
initial begin
    for(k = 0; k < NUM_SETS; k = k + 1) begin
        valid1[k] = 0;
        valid2[k] = 0;
        valid3[k] = 0;
        valid4[k] = 0;
        
        dirty1[k] = 0;
        dirty2[k] = 0;
        dirty3[k] = 0;
        dirty4[k] = 0;

        lru1[k] = 2'b00;
        lru2[k] = 2'b00;
        lru3[k] = 2'b00;
        lru4[k] = 2'b00;
    end
end

// internal register
reg rg_hit_miss = 1'b0;
reg [WIDTH-1:0] rg_data_ca2cpu = {WIDTH{1'b0}};
reg [MEM_WIDTH-1:0] rg_data_ca2mem = {MEM_WIDTH{1'b0}};
reg [WIDTH-1:0] rg_addr2write_mem = {WIDTH{1'b0}};
reg rg_mem_wren = 1'b0;

// output assignment of internal register -> làm rõ loại mạch là tuần tự hay tổ hợp, hỗ trợ thiết kế đồng bộ hóa, ổn định, dễ tổng hợp, debug, tối ưus
assign hit_miss = rg_hit_miss;
assign mem_rden = !((valid1[address[`SET]] && (tag1[address[`SET]] == address[`TAG]))
                            || (valid2[address[`SET]] && (tag2[address[`SET]] == address[`TAG]))
                            || (valid3[address[`SET]] && (tag3[address[`SET]] == address[`TAG]))
                            || (valid4[address[`SET]] && (tag4[address[`SET]] == address[`TAG])));

assign mem_wren = rg_mem_wren;
assign data_ca2mem = rg_data_ca2mem;
assign data_ca2cpu = rg_data_ca2cpu;
assign addr2read_mem = {address[`TAG], address[`SET]};
assign addr2write_mem = rg_addr2write_mem;

// state parameters
parameter IDLE = 1'b0;              // đợi tín hiệu từ cpu 
parameter MISS = 1'b1;

// state register
reg state = IDLE;


// Finite State Machine
always @(posedge clock) begin
    case(state)
        IDLE: begin 
            // reset write enable phòng khi nó turn on
            rg_mem_wren <= 1'b0;

            // check hit/miss
            // truy cập vào 1 set (cache line) kiểm tra valid, so sánh tag và chọn way
            rg_hit_miss <= ((valid1[address[`SET]] && (tag1[address[`SET]] == address[`TAG]))
                            || (valid2[address[`SET]] && (tag2[address[`SET]] == address[`TAG]))
                            || (valid3[address[`SET]] && (tag3[address[`SET]] == address[`TAG]))
                            || (valid4[address[`SET]] && (tag4[address[`SET]] == address[`TAG])));
            
            // không làm gì nếu k nhận được tín hiệu đọc hay ghi từ cpu
            if(~read_en && ~write_en) begin
                state <= IDLE;
            end
            // CHECK WAY 1
            else if(valid1[address[`SET]] && (tag1[address[`SET]] == address[`TAG])) begin
                // read hit
                if(read_en) begin
                    case(address[`OFFSET]) 
                        WORD1: rg_data_ca2cpu <= data1[address[`SET]][WIDTH-1:0];
                        WORD2: rg_data_ca2cpu <= data1[address[`SET]][2*WIDTH-1:WIDTH];
                    endcase
                end
                // write hit
                else if(write_en) begin
                    rg_data_ca2cpu = {WIDTH{1'b0}};
                    dirty1[address[`SET]] <= 1'b1;
                    if(address[`OFFSET] <= WORD1) begin // nếu ghi word1 thì gán vào word đầu của cache 
                        data1[address[`SET]][WIDTH-1:0] <= cpu_data;
                    end
                    else begin // ghi vào word2 của cache
                        data1[address[`SET]][2*WIDTH-1:WIDTH] <= cpu_data;
                    end
                end
                
                // update LRU bit
                if(lru2[address[`SET]] <= lru1[address[`SET]]) begin
                    lru2[address[`SET]] <= lru2[address[`SET]] + 1;
                end
                if(lru3[address[`SET]] <= lru1[address[`SET]]) begin
                    lru3[address[`SET]] <= lru3[address[`SET]] + 1;
                end
                if(lru4[address[`SET]] <= lru1[address[`SET]]) begin
                    lru4[address[`SET]] <= lru4[address[`SET]] + 1;
                end
                lru1[address[`SET]] <= 0;
            end
            // CHECK WAY 2
            else if(valid2[address[`SET]] && (tag2[address[`SET]] == address[`TAG])) begin
                // read hit
                if(read_en) begin
                    case(address[`OFFSET])
                        WORD1: rg_data_ca2cpu <= data2[address[`SET]][WIDTH-1:0];
                        WORD2: rg_data_ca2cpu <= data2[address[`SET]][2*WIDTH-1:WIDTH];
                    endcase
                end
                // write hit
                else if(write_en) begin
                    rg_data_ca2cpu = {WIDTH{1'b0}};
                    dirty2[address[`SET]] <= 1'b1;
                    if(address[`OFFSET] <= WORD1) begin // nếu ghi word1 thì gán vào word đầu của cache 
                        data2[address[`SET]][WIDTH-1:0] <= cpu_data;
                    end
                    else begin // ghi vào word2 của cache
                        data2[address[`SET]][2*WIDTH-1:WIDTH] <= cpu_data;
                    end
                end
                
                // update LRU bit
                if(lru1[address[`SET]] <= lru2[address[`SET]]) begin
                    lru1[address[`SET]] <= lru1[address[`SET]] + 1;
                end
                if(lru3[address[`SET]] <= lru2[address[`SET]]) begin
                    lru3[address[`SET]] <= lru3[address[`SET]] + 1;
                end
                if(lru4[address[`SET]] <= lru2[address[`SET]]) begin
                    lru4[address[`SET]] <= lru4[address[`SET]] + 1;
                end
                lru2[address[`SET]] <= 0;
            end

            // CHECK WAY 3
            else if(valid3[address[`SET]] && (tag3[address[`SET]] == address[`TAG])) begin
                // read hit
                if(read_en) begin
                    case(address[`OFFSET])
                        WORD1: rg_data_ca2cpu <= data3[address[`SET]][WIDTH-1:0];
                        WORD2: rg_data_ca2cpu <= data3[address[`SET]][2*WIDTH-1:WIDTH];
                    endcase
                end
                // write hit
                else if(write_en) begin
                    rg_data_ca2cpu = {WIDTH{1'b0}};
                    dirty3[address[`SET]] <= 1'b1;
                    if(address[`OFFSET] <= WORD1) begin // nếu ghi word1 thì gán vào word đầu của cache 
                        data3[address[`SET]][WIDTH-1:0] <= cpu_data;
                    end
                    else begin // ghi vào word2 của cache
                        data3[address[`SET]][2*WIDTH-1:WIDTH] <= cpu_data;
                    end
                end
                
                // update LRU bit
                if(lru1[address[`SET]] <= lru3[address[`SET]]) begin
                    lru1[address[`SET]] <= lru1[address[`SET]] + 1;
                end
                if(lru2[address[`SET]] <= lru3[address[`SET]]) begin
                    lru2[address[`SET]] <= lru2[address[`SET]] + 1;
                end
                if(lru4[address[`SET]] <= lru3[address[`SET]]) begin
                    lru4[address[`SET]] <= lru4[address[`SET]] + 1;
                end
                lru3[address[`SET]] <= 0;
            end

            // CHECK WAY 4
            else if(valid4[address[`SET]] && (tag4[address[`SET]] == address[`TAG])) begin
                // read hit
                if(read_en) begin
                    case(address[`OFFSET])
                        WORD1: rg_data_ca2cpu <= data4[address[`SET]][WIDTH-1:0];
                        WORD2: rg_data_ca2cpu <= data4[address[`SET]][2*WIDTH-1:WIDTH];
                    endcase
                end
                // write hit
                else if(write_en) begin
                    rg_data_ca2cpu = {WIDTH{1'b0}};
                    dirty4[address[`SET]] <= 1'b1;
                    if(address[`OFFSET] <= WORD1) begin // nếu ghi word1 thì gán vào word đầu của cache 
                        data4[address[`SET]][WIDTH-1:0] <= cpu_data;
                    end
                    else begin // ghi vào word2 của cache
                        data4[address[`SET]][2*WIDTH-1:WIDTH] <= cpu_data;
                    end
                end
                
                // update LRU bit
                if(lru1[address[`SET]] <= lru4[address[`SET]]) begin
                    lru1[address[`SET]] <= lru1[address[`SET]] + 1;
                end
                if(lru2[address[`SET]] <= lru4[address[`SET]]) begin
                    lru2[address[`SET]] <= lru2[address[`SET]] + 1;
                end
                if(lru3[address[`SET]] <= lru4[address[`SET]]) begin
                    lru3[address[`SET]] <= lru3[address[`SET]] + 1;
                end
                lru4[address[`SET]] <= 0;
            end

            // MISS
            else begin
                state <= MISS;
            end
        end

        MISS: begin
            // if 1 way invalid -> no need to evict
            if(~valid1[address[`SET]]) begin
                data1[address[`SET]] <= addr2write_mem; // assign data
                tag1[address[`SET]] <= address[`TAG];   // assign tag
                dirty1[address[`SET]] <= 0;
                valid1[address[`SET]] <= 1;
            end
            else if(~valid2[address[`SET]]) begin
                data2[address[`SET]] <= addr2write_mem;
                tag2[address[`SET]] <= address[`TAG];
                dirty2[address[`SET]] <= 0;
                valid2[address[`SET]] <= 1;
            end
            else if(~valid3[address[`SET]]) begin
                data3[address[`SET]] <= addr2write_mem;
                tag3[address[`SET]] <= address[`TAG];
                dirty3[address[`SET]] <= 0;
                valid3[address[`SET]] <= 1;
            end
            else if(~valid4[address[`SET]]) begin
                data4[address[`SET]] <= addr2write_mem;
                tag4[address[`SET]] <= address[`TAG];
                dirty4[address[`SET]] <= 0;
                valid4[address[`SET]] <= 1;
            end

            // LRU
            // way 1 is LRU
            else if(lru1[address[`SET]] == 2'b11) begin
                if(dirty1[address[`SET]] == 1) begin // write back
                    rg_addr2write_mem <= {tag1[address[`SET]], address[`SET]}; // tag and set
                    rg_mem_wren <= 1; // enable write RAM
                    rg_data_ca2mem <= data1[address[`SET]]; // write content from cache (block) to RAM
                end
                // write allocate
                data1[address[`SET]] <= mem_data; // load block from RAM to cache
                tag1[address[`SET]] <= address[`TAG]; // update tag
                dirty1[address[`SET]] <= 0; // new block -> set dirty = 0
                valid1[address[`SET]] <= 1; // block valid
            end

            // way 2 is LRU
            else if(lru2[address[`SET]] == 2'b11) begin
                if(dirty2[address[`SET]] == 1) begin
                    rg_addr2write_mem <= {tag2[address[`SET]], address[`SET]}; // tag and set
                    rg_mem_wren <= 1; // enable write
                    rg_data_ca2mem <= data2[address[`SET]];
                end
                data2[address[`SET]] <= mem_data;
                tag2[address[`SET]] <= address[`TAG];
                dirty2[address[`SET]] <= 0;
                valid2[address[`SET]] <= 1;
            end

            // way 3 is LRU
            else if(lru3[address[`SET]] == 2'b11) begin
                if(dirty3[address[`SET]] == 1) begin
                    rg_addr2write_mem <= {tag3[address[`SET]], address[`SET]}; // tag and set
                    rg_mem_wren <= 1; // enable write
                    rg_data_ca2mem <= data3[address[`SET]];
                end
                data3[address[`SET]] <= mem_data;
                tag3[address[`SET]] <= address[`TAG];
                dirty3[address[`SET]] <= 0;
                valid3[address[`SET]] <= 1;
            end

            // way 4 is LRU
            else if(lru4[address[`SET]] == 2'b11) begin
                if(dirty4[address[`SET]] == 1) begin
                    rg_addr2write_mem <= {tag4[address[`SET]], address[`SET]}; // tag and set
                    rg_mem_wren <= 1; // enable write
                    rg_data_ca2mem <= data4[address[`SET]];
                end
                data4[address[`SET]] <= mem_data;
                tag4[address[`SET]] <= address[`TAG];
                dirty4[address[`SET]] <= 0;
                valid4[address[`SET]] <= 1;
            end

            // no valid, no lru
            state <= IDLE;
        end

        default: state <= IDLE;
    endcase 
end

endmodule

