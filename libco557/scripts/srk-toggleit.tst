load toggle.asm,
output-file srk-toggleit.out,
output-list RAM[16384]%B1.16.1 RAM[24575]%B1.16.1 RAM[18758]%B1.16.1 RAM[16847]%B1.16.1 RAM[16835]%B1.16.1;

        set RAM[24576] 65,

        repeat 800000 {
          ticktock;
        }
        
        set RAM[24576] 0,
        repeat 800000 {
          ticktock;
        }

        set RAM[24576] 65,

        repeat 800000 {
          ticktock;
        }
        
        set RAM[24576] 0,
        repeat 800000 {
          ticktock;
        }

        set RAM[24576] 65,

        repeat 800000 {
          ticktock;
        }
        
        set RAM[24576] 0,
        repeat 800000 {
          ticktock;
        }

        set RAM[24576] 65,

        repeat 800000 {
          ticktock;
        }
        
        set RAM[24576] 0,
        repeat 800000 {
          ticktock;
        }

        repeat 800000 {
              ticktock;
            }
        output;
