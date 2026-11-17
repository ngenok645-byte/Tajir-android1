import "jsr:@supabase/functions-js/edge-runtime.d.ts"; import { createClient } from "npm:@supabase/supabase-js@2";
Deno.serve(async (req) => { if(req.method==="OPTIONS") return new Response("ok"); if(req.method!=="POST") return new Response("POST required",{status:405});
try { const b=await req.json(); if(typeof b.phone!=="string"||typeof b.pin!=="string"||typeof b.full_name!=="string"||!/^\d{6}$/.test(b.pin)||b.full_name.trim().length<2) return Response.json({error:"Enter name, Kenyan phone and six-digit PIN."},{status:400});
const d=b.phone.replace(/[^0-9]/g,""); const phone=d.startsWith("254")?"+"+d:d.startsWith("0")?"+254"+d.slice(1):"+254"+d; if(!/^\+254\d{9}$/.test(phone)) return Response.json({error:"Invalid Kenyan phone."},{status:400});
const db=createClient(Deno.env.get("SUPABASE_URL")!,Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,{auth:{persistSession:false}});
const ip=req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||"unknown";
const {data:ok,error:re}=await db.rpc("consume_tajir_registration_attempt",{p_phone:phone,p_ip:ip}); if(re) throw re; if(ok!==true) return Response.json({error:"Too many attempts. Try later."},{status:429});
const email="u"+phone.replace(/\D/g,"")+"@login.tajir.app"; const {data,error}=await db.auth.admin.createUser({email,password:b.pin,email_confirm:true,user_metadata:{display_name:b.full_name.trim(),full_name:b.full_name.trim()}}); if(error) throw error;
const {error:pe}=await db.from("profiles").update({phone,display_name:b.full_name.trim(),status:"pending"}).eq("id",data.user.id); if(pe){await db.auth.admin.deleteUser(data.user.id);throw pe;}
return Response.json({success:true}); } catch(e){return Response.json({error:e instanceof Error?e.message:"Registration failed."},{status:400});}});
