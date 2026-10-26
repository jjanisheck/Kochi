// Lossless FBX binary node reader/writer. Geometry/animation array properties
// stay compressed and byte-identical; only explicit node edits are serialized.
const MAGIC = Buffer.from('Kaydara FBX Binary  \0\x1a\0','binary');

export function stringProperty(value) {
  const bytes=Buffer.from(value,'utf8'), header=Buffer.alloc(5);
  header[0]=83; header.writeUInt32LE(bytes.length,1);
  return {type:'S',value,raw:Buffer.concat([header,bytes])};
}

export function binaryProperty(bytes) {
  const header=Buffer.alloc(5); header[0]=82; header.writeUInt32LE(bytes.length,1);
  return {type:'R',value:bytes,raw:Buffer.concat([header,bytes])};
}

export function parseBinaryFBX(bytes) {
  if (!bytes.subarray(0,23).equals(MAGIC)) throw new Error('Expected a binary FBX file.');
  const version=bytes.readUInt32LE(23), wide=version>=7500, headerSize=wide?25:13;
  const uint=(offset)=>wide?Number(bytes.readBigUInt64LE(offset)):bytes.readUInt32LE(offset);
  function property(offset) {
    const start=offset, type=String.fromCharCode(bytes[offset++]);
    let value;
    if ('SR'.includes(type)) {
      const length=bytes.readUInt32LE(offset); offset+=4;
      const payload=bytes.subarray(offset,offset+length); offset+=length;
      value=type==='S'?payload.toString('utf8'):payload;
    } else if (type==='L') { value=bytes.readBigInt64LE(offset); offset+=8; }
    else if (type==='I') { value=bytes.readInt32LE(offset); offset+=4; }
    else if (type==='Y') { value=bytes.readInt16LE(offset); offset+=2; }
    else if (type==='C') { value=bytes[offset++]; }
    else if (type==='D') { value=bytes.readDoubleLE(offset); offset+=8; }
    else if (type==='F') { value=bytes.readFloatLE(offset); offset+=4; }
    else if ('fdlibc'.includes(type)) { const length=bytes.readUInt32LE(offset+8); offset+=12+length; }
    else throw new Error(`Unsupported FBX property ${type} at ${start}.`);
    if (offset>bytes.length) throw new Error('FBX property extends beyond the file.');
    return {property:{type,value,raw:bytes.subarray(start,offset)},offset};
  }
  function node(offset) {
    const end=uint(offset);
    if (end===0) return {node:null,offset:offset+headerSize};
    if (end<=offset || end>bytes.length) throw new Error(`Invalid FBX node end at ${offset}.`);
    const count=uint(offset+(wide?8:4)), propertyLength=uint(offset+(wide?16:8));
    const nameLength=bytes[offset+headerSize-1];
    const name=bytes.toString('utf8',offset+headerSize,offset+headerSize+nameLength);
    offset+=headerSize+nameLength;
    const properties=[], propertyEnd=offset+propertyLength;
    for (let i=0;i<count;i++) { const next=property(offset); properties.push(next.property); offset=next.offset; }
    if (offset!==propertyEnd) throw new Error(`Wrong property length in ${name}.`);
    const children=[]; let terminator=false;
    while (offset<end) {
      const next=node(offset); offset=next.offset;
      if (!next.node) { terminator=true; break; }
      children.push(next.node);
    }
    if (offset!==end) throw new Error(`Wrong node length in ${name}.`);
    return {node:{name,properties,children,terminator},offset};
  }
  const nodes=[]; let offset=27;
  while (offset<bytes.length) {
    const next=node(offset); offset=next.offset;
    if (!next.node) break;
    nodes.push(next.node);
  }
  return {version,header:bytes.subarray(0,27),nodes,footer:bytes.subarray(offset),originalFooterOffset:offset};
}

export function encodeBinaryFBX(document) {
  const wide=document.version>=7500, headerSize=wide?25:13;
  function nodeSize(node) {
    return headerSize+Buffer.byteLength(node.name)+node.properties.reduce((n,p)=>n+p.raw.length,0)+node.children.reduce((n,c)=>n+nodeSize(c),0)+(node.terminator?headerSize:0);
  }
  function encode(node,start) {
    const name=Buffer.from(node.name), size=nodeSize(node), header=Buffer.alloc(headerSize);
    const props=Buffer.concat(node.properties.map(p=>p.raw));
    if (wide) {
      header.writeBigUInt64LE(BigInt(start+size),0); header.writeBigUInt64LE(BigInt(node.properties.length),8); header.writeBigUInt64LE(BigInt(props.length),16);
    } else {
      header.writeUInt32LE(start+size,0); header.writeUInt32LE(node.properties.length,4); header.writeUInt32LE(props.length,8);
    }
    header[headerSize-1]=name.length;
    const chunks=[header,name,props]; let offset=start+header.length+name.length+props.length;
    for (const child of node.children) { const data=encode(child,offset); chunks.push(data); offset+=data.length; }
    if (node.terminator) chunks.push(Buffer.alloc(headerSize));
    return Buffer.concat(chunks);
  }
  const chunks=[document.header]; let offset=27;
  for (const node of document.nodes) { const bytes=encode(node,offset); chunks.push(bytes); offset+=bytes.length; }
  chunks.push(Buffer.alloc(headerSize)); offset+=headerSize;
  // The first footer block is a 16-byte magic followed by alignment padding.
  // Keep the original footer payload and adjust only that padding if needed.
  let footer=document.footer;
  const oldPad=(16-(document.originalFooterOffset+16)%16)%16;
  const newPad=(16-(offset+16)%16)%16;
  if (footer.length>=16+oldPad && footer.subarray(16,16+oldPad).every(byte=>byte===0)) {
    footer=Buffer.concat([footer.subarray(0,16),Buffer.alloc(newPad),footer.subarray(16+oldPad)]);
  }
  chunks.push(footer);
  return Buffer.concat(chunks);
}

export function child(node,name) { return node.children.find(node=>node.name===name); }
export function text(node,name) { return child(node,name)?.properties[0]?.value; }
