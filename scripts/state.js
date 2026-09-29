const cards=[
 {name:'Juan Manuel Fangio',short:'FANGIO',year:1954,rating:98,rarity:'legend',type:'LEGEND',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/ca/Beaufort_at_1961_Dutch_Grand_Prix_%282%29.jpg/960px-Beaufort_at_1961_Dutch_Grand_Prix_%282%29.jpg'},
 {name:'Ayrton Senna',short:'SENNA',year:1990,rating:94,rarity:'icon',type:'ICON',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/0/06/ClarkJim-Lotus19620805.jpg/960px-ClarkJim-Lotus19620805.jpg'},
 {name:'Michael Schumacher',short:'SCHUMACHER',year:2001,rating:91,rarity:'epic',type:'EPIC',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a3/2004_Williams_FW26.jpg/960px-2004_Williams_FW26.jpg'},
 {name:'Lewis Hamilton',short:'HAMILTON',year:2020,rating:88,rarity:'rare',type:'RARE',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c0/2022_British_Grand_Prix_%2852382575808%29.jpg/960px-2022_British_Grand_Prix_%2852382575808%29.jpg'},
 {name:'Max Verstappen',short:'VERSTAPPEN',year:2023,rating:85,rarity:'rare',type:'RARE',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a2/2015_Malaysian_GP_opening_lap.jpg/960px-2015_Malaysian_GP_opening_lap.jpg'},
 {name:'Alain Prost',short:'PROST',year:1988,rating:90,rarity:'epic',type:'EPIC',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d6/1985_European_GP_Brundle_02.jpg/960px-1985_European_GP_Brundle_02.jpg'},
 {name:'Kimi Räikkönen',short:'RÄIKKÖNEN',year:2007,rating:82,rarity:'rare',type:'RARE',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/1/1c/2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Fernando_Alonso_%2840970600574%29.jpg'},
 {name:'Nico Rosberg',short:'ROSBERG',year:2013,rating:83,rarity:'rare',type:'RARE',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/2/25/Drivers_at_1969_Dutch_Grand_Prix.jpg/960px-Drivers_at_1969_Dutch_Grand_Prix.jpg'},
 {name:'Nigel Mansell',short:'MANSELL',year:1992,rating:87,rarity:'rare',type:'RARE',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/d/d5/Grand_Prix_Zandvoort_1966_Taylor%2C_Bestanddeelnr_919-3828.jpg/960px-Grand_Prix_Zandvoort_1966_Taylor%2C_Bestanddeelnr_919-3828.jpg'},
 {name:'Ferrari F2004',short:'F2004',year:2004,rating:94,rarity:'icon',type:'CAR',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/a/a3/2004_Williams_FW26.jpg/960px-2004_Williams_FW26.jpg'},
 {name:'McLaren MP4/4',short:'MP4/4',year:1988,rating:96,rarity:'legend',type:'CAR',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/b/b6/Lotus_95T_Elio_De_Angelis_Detroit_Grand_Prix_1984a.jpeg/960px-Lotus_95T_Elio_De_Angelis_Detroit_Grand_Prix_1984a.jpeg'},
 {name:'Red Bull RB19',short:'RB19',year:2023,rating:92,rarity:'icon',type:'CAR',img:'https://thumb.wikimedia.org/wikipedia/commons/thumb/c/c6/2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg/960px-2018_Chinese_Grand_Prix_FP3_Charles_Leclerc_%2839897914770%29.jpg'}
];
let coins=0, points=0, selectedPack={name:'GOLD PACK',cost:9500,type:'gold'};
let currentUser=null, accountProfile=null, userCards=[], isAdmin=false;
let showroomTimer=null, showroomCountdown=null;
let confettiTimer=null, confettiCleanupTimer=null, inspectTimer=null, stageFinishTimer=null;
let openingAudioContext=null;
