import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(status:number,value:Record<string,unknown>)=>new Response(JSON.stringify(value),{status,headers:{...cors,"Content-Type":"application/json"}});
function normalizePhone(value:string){const d=value.replace(/[^0-9]/g,"");if(d.startsWith("254")&&d.length===12)return `+${d}`;if(d.startsWith("0")&&d.length===10)return `+254${d.slice(1)}`;if(d.length===9)return `+254${d}`;throw new Error("Enter a valid Kenyan phone number.");}
const loginEmail=(phone:string)=>`u${phone.replace(/[^0-9]/g,"")}@login.tajir.app`;
Deno.serve(async(req)=>{
 if(req.method==="OPTIONS")return new Response("ok",{headers:cors});
 if(req.method!=="POST")return json(405,{error:"POST required."});
 let createdUserId:string|null=null;
 try{
  const body=await req.json();
  if(typeof body.full_name!=="string"||body.full_name.trim().length<2||body.full_name.trim().length>80)return json(400,{error:"Enter your full name."});
  if(typeof body.phone!=="string"||typeof body.pin!=="string"||!/^\d{6}$/.test(body.pin))return json(400,{error:"Enter a valid Kenyan phone number and six-digit PIN."});
  const phone=normalizePhone(body.phone);
  const url=Deno.env.get("SUPABASE_URL");const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if(!url||!key)return json(500,{error:"Authentication service is not configured."});
  const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
  const ip=req.headers.get("cf-connecting-ip")||req.headers.get("x-real-ip")||(req.headers.get("x-forwarded-for")||"unknown").split(",")[0].trim();
  const {data:allowed,error:rateError}=await db.schema("private").rpc("consume_tajir_registration_attempt",{p_phone:phone,p_ip:ip});
  if(rateError)throw rateError;
  if(allowed!==true)return json(429,{error:"Too many registration attempts. Please wait before trying again."});
  const localPhone=`0${phone.slice(4)}`;
  const {data:existing,error:lookupError}=await db.from("profiles").select("id").in("phone",[phone,localPhone,body.phone.trim()]).limit(1);
  if(lookupError)throw lookupError;
  if(existing?.length)return json(409,{error:"An account already exists for this phone number. Please sign in."});
  const {data,error}=await db.auth.admin.createUser({email:loginEmail(phone),password:body.pin,email_confirm:true,user_metadata:{display_name:body.full_name.trim(),full_name:body.full_name.trim()}});
  if(error)throw error;
  createdUserId=data.user.id;
  const {error:profileError}=await db.from("profiles").update({phone,display_name:body.full_name.trim(),status:"pending"}).eq("id",createdUserId);
  if(profileError)throw profileError;
  return json(200,{success:true,message:"Account created. Sign in to continue; approval is required."});
 }catch(e){
  if(createdUserId){const url=Deno.env.get("SUPABASE_URL");const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(url&&key){const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});await db.auth.admin.deleteUser(createdUserId);}}
  return json(400,{error:e instanceof Error?e.message:"Registration failed."});
 }
});
