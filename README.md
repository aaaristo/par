PAR: PL/SQL Archive
=======

## a jar for plsql
PAR is a plsql package that creates some other plsql packages (called PARs),
that are really archives: those packages can contains ***java classes*** and any plsql code,
so that you can export and deploy your libraries in some other schema/instance 
simply compiling the par and executing its deploy procedure. For those who hate loadjava.


## 1. create a par
this is a sample creating a PAR for a package i use to read/write excel files in plsql
this code will generate a pl/sql package named par_excel

<pre>
begin
   
   par_creator.new_par('excel');
   par_creator.add_package('pkg_excel',true,false);
   
   for c_cur in (select object_name, dbms_java.longname(object_name) long_name 
                   from user_objects 
                  where object_type= 'JAVA CLASS'
                    and status= 'VALID') 
   loop
      par_creator.add_java_class(c_cur.long_name);
   end loop;
   
   for c_cur in (select object_name, dbms_java.longname(object_name) long_name 
                   from user_objects 
                  where object_type= 'JAVA RESOURCE') 
   loop
      par_creator.add_java_resource(c_cur.long_name);
   end loop;
   
   par_creator.close_par;
   par_creator.compile_par;
   
end;
</pre>


## 2. compile to another schema
then you can take the generated PAR (par_excel package) and compile it 
into another oracle schema

## 3. deploy its contents!

<pre>
begin
 par_excel.deploy;
end;
</pre>


easy eh?
actually PARs can contain (and deploy) any PL/SQL source, java sources/classes/resources and xdb files
once created a PAR has no external dependency (it uses only system provided packages to accomplish the deploy)

[![Bitdeli Badge](https://d2weczhvl823v0.cloudfront.net/aaaristo/par/trend.png)](https://bitdeli.com/free "Bitdeli Badge")
