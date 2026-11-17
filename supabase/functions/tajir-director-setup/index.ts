import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "npm:@supabase/supabase-js@2";
const cors={"Access-Control-Allow-Origin":"*","Access-Control-Allow-Headers":"authorization, x-client-info, apikey, content-type","Access-Control-Allow-Methods":"POST, OPTIONS"};
const json=(status:number,value:Record<string,unknown>)=>new Response(JSON.stringify(value),{status,headers:{...cors,"Content-Type":"application/json"}});
function normalizePhone(value:string){const d=value.replace(/[^0-9]/g,"");if(d.startsWith("254")&&d.length===12)return `+${d}`;if(d.startsWith("0")&&d.length===10)return `+254${d.slice(1)}`;if(d.length===9)return `+254${d}`;throw new Error("Enter a valid Kenyan phone number.");}
const loginEmail=(phone:string)=>`u${phone.replace(/[^0-9]/g,"")}@login.tajir.app`;
Deno.serve(async(req)=>{if(req.method==="OPTIONS")return new Response("ok",{headers:cors});if(req.method!=="POST")return json(405,{error:"POST required."});try{
const body=await req.json();if(typeof body.phone!=="string")return json(400,{error:"Enter the registered Director phone number."});
const phone=normalizePhone(body.phone);const localPhone=`0${phone.slice(4)}`;const url=Deno.env.get("SUPABASE_URL");const key=Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");if(!url||!key)return json(500,{error:"Authentication service is not configured."});
const db=createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
const {data:profiles,error}=await db.from("profiles").select("id,status,director_bootstrap_claimed_at").in("phone",[body.phone.trim(),localPhone,phone]).limit(2);if(error)throw error;if(!profiles||profiles.length!==1)return json(403,{error:"No unique Director account matches this phone."});
const p=profiles[0];if(p.status!=="active"||!p.director_bootstrap_claimed_at)return json(403,{error:"Director account has not completed its approved setup."});
const {data:roles,error:roleError}=await db.from("user_role_assignments").select("app_roles!inner(code)").eq("user_id",p.id).eq("is_active",true);if(roleError)throw roleError;if(!roles?.some((r:any)=>r.app_roles?.code==="director"))return json(403,{error:"This account is not assigned the Director role."});
const {error:updateError}=await db.auth.admin.updateUserById(p.id,{email:loginEmail(phone),email_confirm:true});if(updateError)throw updateError;
return json(200,{success:true,message:"Director phone login has been prepared. Use your existing PIN."});
}catch(e){return json(400,{error:e instanceof Error?e.message:"Director login setup failed."});}});
