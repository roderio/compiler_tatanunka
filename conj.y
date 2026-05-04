%skeleton "lalr1.cc"
%define api.parser.class {conj_parser}
%define api.token.constructor
%define api.value.type variant
%define parse.assert
%define parse.error verbose
%locations

%code requires
{
    #include <map>
    #include <list>
    #include <vector>
    #include <string>
    #include <iostream>
    #include <algorithm>
    // list of identifier types
    #define ENUM_IDENTIFIERS(o) \
            o(undefined)        \
            o(function)        \
            o(parameter)        \
            o(variable)
    #define o(n) n,
    enum class id_type { ENUM_IDENTIFIERS(o) };  
    #undef o
    struct identifier
    {
        id_type type =  id_type::undefined;
        std::size_t     index = 0;
        std::string     name;
    };

    #define ENUM_EXPRESSIONS(o) \
            o(nop) o(string) o(number) o(ident)\
            o(add) o(neg) o(eq)\
            o(cor) o(cand) o(loop)\
            o(addrof) o(deref)\
            o(fcall)\
            o(copy)\
            o(comma)\
            o(ret)
    #define o(n) n,
    enum class ex_type { ENUM_EXPRESSIONS(o) };
    #undef o

    typedef std::list<struct expression> expr_vec;
    struct expression
    {
        ex_type type;
        identifier      ident{};
        std::string     strvalue{};
        long            numvalue=0;
        expr_vec        params;

        template<typename... T>
        expression(ex_type t, T&&... args)  : type(t), params{std::forward<T>(args)... } {}

        expression()                        :type(ex_type::nop) {}
        expression(const identifier& i)     :type(ex_type::ident), ident(i) {}
        expression(identifier&& i)          :type(ex_type::ident), ident(std::move(i)) {}
        expression(std::string&& s)         :type(ex_type::string), strvalue(std::move(s)) {}
        expression(long v)                  :type(ex_type::number), numvalue(v) {}

        bool is_pure() const;
        bool is_compiletime_expr() const;
        expression operator%=(expression&& b) && {return expression(ex_type::copy, std::move(b), std::move(*this));}
    };

    #define o(n)\
    inline bool is_##n(const identifier& i){ return i.type == id_type::n;}
    ENUM_IDENTIFIERS(o)
    #undef o

    #define o(n)\
    inline bool is_##n(const expression& e){ return e.type == ex_type::n;} \
    template<typename... T>\
    inline expression e_##n(T&&... args) { return expression(ex_type::n, std::forward<T>(args)...); }
    ENUM_EXPRESSIONS(o)
    #undef o

    struct function
    {
        std::string name;
        expression code;
        unsigned num_vars = 0, num_params = 0;
        bool     pure     = false, pure_known = false;

        expression maketemp() { expression r(identifier {id_type::variable, num_vars, "$C" + std::to_string(num_vars)}); ++num_vars; return r;}
    };

    struct lexcontext;
}//%code requires

%parse-param { lexcontext& ctx }
%lex-param   { lexcontext& ctx }
%code
{
struct lexcontext
{
    const char* cursor;
    yy::location loc;
    std::vector<std::map<std::string, identifier>> scopes;
    std::vector<function> func_list;
    unsigned tempcounter = 0;
    function fun;
    public:
        const identifier& define(const std::string& name, identifier&& f)
        {
            auto r = scopes.back().emplace(name, std::move(f));
            if(!r.second) throw std::runtime_error("Duplicate definition <" + name + ">");;
            return r.first->second;
        }
        expression def(const std::string& name)     { return define(name, identifier {id_type::variable, fun.num_vars++, name}); }
        expression defun(const std::string& name)   { return define(name, identifier {id_type::function, func_list.size(), name}); }
        expression defparm(const std::string& name) { return define(name, identifier {id_type::parameter, fun.num_params++, name}); }
        expression temp()                           { return def("$I" + std::to_string(tempcounter++)); }
        expression use(const std::string& name)
        {
            for(auto j = scopes.crbegin(); j!=scopes.crend(); ++j)
                if(auto i = j->find(name); i!=j->end())
                    return i->second;
            throw std::runtime_error("Undefined identifier <" + name + ">");
        }
        void add_function(std::string&& name, expression&& code)
        {
            fun.code = e_comma(std::move(code), e_ret(0l));
            fun.name = std::move(name);
            func_list.push_back(std::move(fun));
            fun = {};
        }
        void operator ++() { scopes.emplace_back();}
        void operator --() { scopes.pop_back();}
};

namespace yy{ conj_parser::symbol_type yylex(lexcontext& ctx); }

#define M(x) std::move(x)
#define C(x) expression(x)

}//%code


%token                  END 0
%token                  RETURN "return" WHILE "while" IF "if" VAR "var"
%token <long>           NUMCONST
%token <std::string>    IDENTIFIER STRINGCONST
%token                  OR "||" AND "&&" EQ "==" NE "!=" PP "++" MM "--" PL_EQ "+=" MI_EQ "-="
%left                   ','
%right                  '?' ':' '=' "+=" "-="
%left                   "||"
%left                   "&&"
%left                   "==" "!="
%left                   '+' '-'
%left                   '*'
%right                  '&' "++" "--"
%left                   '(' '['
%type<std::string>      identifier1
%type<expression>       expr expr1 exprs exprs1 c_expr1 p_expr1 stmt stmt1 var_defs var_def1 com_stmt
%%

library:    { ++ctx; } functions { ++ctx; };
functions:  functions identifier1 {ctx.defun($2); ++ctx; } paramdecls colon1 stmt1 {ctx.add_function(M($2), M($6)); --ctx; }
|           %empty;
paramdecls: paramdecl 
|           %empty;
paramdecl:  paramdecl ',' identifier1                                   {ctx.defparm($3); }
|           IDENTIFIER                                                  {ctx.defparm($1); };
identifier1:IDENTIFIER                                                  {$$ = M($1);};
colon1:     ':';
semicolon1: ';';
cl_brace1:  '}';
cl_bracket1:']';
cl_parens1: ')';
stmt1:      stmt                                                        {$$ = M($1);};     
exprs1:     exprs                                                       {$$ = M($1);};     
expr1:      expr                                                        {$$ = M($1);};     
p_expr1:    '(' exprs1 cl_parens1                                       {$$ = M($2);};     
stmt:       com_stmt        cl_brace1                                   {$$ = M($1); --ctx; }
|           "if" p_expr1 stmt1                                          {$$ = e_cand(M($2), M($3)); }
|           "while" p_expr1 stmt1                                       {$$ = e_loop(M($2), M($3)); }
|           "return" exprs      semicolon1                              {$$ = e_ret(M($2)); }
|           exprs               semicolon1                              {$$ = M($1); }
|                               semicolon1                              { };
com_stmt:   '{'                                                         {$$ = e_comma(); ++ctx; }
|           com_stmt stmt                                               {$$ = M($1); $$.params.push_back(M($2)); };
var_defs:   "var"   var_def1                                            {$$ = e_comma(M($2)); }
|           var_defs ','  var_def1                                      {$$ = M($1); $$.params.push_back(M($3)); }
var_def1:   identifier1 '=' expr                                        {$$ = ctx.def($1) %= M($3);}
|           identifier1                                                 {$$ = ctx.def($1) %= 0l;};
exprs:      var_defs                                                    {$$ = M($1);}
|           expr                                                        {$$ = M($1);}
|           expr    ',' c_expr1                                         {$$ = e_comma(M($1)); $$.params.splice($$.params.end(), M($3.params)); };
c_expr1:    expr1                                                       {$$ = e_comma(M($1)); }
|           c_expr1 ',' expr1                                           {$$ = M($1); $$.params.push_back(M($3)); };
expr:       NUMCONST                                                    {$$ = $1;}
|           STRINGCONST                                                 {$$ = M($1);}
|           IDENTIFIER                                                  {$$ = ctx.use($1);};
|           '(' exprs cl_parens1                                         {$$ = M($2);}
|           expr '[' exprs1 cl_bracket1                                 {$$ = e_deref(e_add(M($1), M($3))); }
|           expr '(' cl_parens1                                         {$$ = e_fcall(M($1));}
|           expr '(' c_expr1 cl_parens1                                 {$$ = e_fcall(M($1)); $$.params.splice($$.params.end(), M($3.params)); }
|   expr '=' error {$$ = M($1);}    |                                    expr '=' expr                   {$$ = M($1)%= M($3); }
|   expr '+' error {$$ = M($1);}    |                                    expr '+' expr                   {$$ = e_add(M($1), M($3)); }
|   expr '-' error {$$ = M($1);}    |                                    expr '-' expr   %prec '+'       {$$ = e_add(M($1), e_neg(M($3))); }
|   expr "+=" error {$$ = M($1);}   |                                    expr "+=" expr                  { if(!$3.is_pure()){$$ = ctx.temp() %= e_addrof(M($1)); $1= e_deref($$.params.back());}
                                                                         $$ = e_comma (M($$), M($1) %= e_add(C($1), M($3))); }
|   expr "-=" error {$$ = M($1);}   |                                    expr "-=" expr                  { if(!$3.is_pure()){$$ = ctx.temp() %= e_addrof(M($1)); $1= e_deref($$.params.back());}
                                                                         $$ = e_comma (M($$), M($1) %= e_add(C($1), e_neg(M($3)))); }
|           expr "++"                                                   { if(!$1.is_pure()){ $$ = ctx.temp() %= e_addrof(M($1)); $1 = e_deref($$.params.back()); }
                                                                         $$ = e_comma(M($$), M($1)%=e_add(C($1), 1l)); }
|           expr "--"       %prec "++"                                  { if(!$1.is_pure()){ $$ = ctx.temp() %= e_addrof(M($1)); $1 = e_deref($$.params.back()); }
                                                                         $$ = e_comma(M($$), M($1)%=e_add(C($1), -1l)); }
|   "++" error {}                   | "++" expr                       { if(!$2.is_pure()){ $$ = ctx.temp() %= e_addrof(M($2)); $2 = e_deref($$.params.back()); }
                                                         auto i = ctx.temp(); $$ = e_comma(M($$), C(i) %= C($2), C($2) %= e_add(C($2), 1l), C(i)); }
|   "--" error {}                   | "--" expr       %prec "++"      { if(!$2.is_pure()){ $$ = ctx.temp() %= e_addrof(M($2)); $2 = e_deref($$.params.back()); }
                                                         auto i = ctx.temp(); $$ = e_comma(M($$), C(i) %= C($2), C($2) %= e_add(C($2), -1l), C(i)); }                       
|   expr "||" error {$$ = M($1);}   |        expr "||" expr                  {$$ = e_cor(M($1), M($3));}
|   expr "&&" error {$$ = M($1);}   |        expr "&&" expr                  {$$ = e_cand(M($1), M($3));}
|   expr "==" error {$$ = M($1);}   |        expr "==" expr                  {$$ = e_eq( M($1), M($3)); }
|   expr "!=" error {$$ = M($1);}   |        expr "!=" expr  %prec "=="      {$$ = e_eq(e_eq( M($1), M($3)), 0l); }
|   '&' error {}                    |        '&' expr                        {$$ = e_addrof(M($2)); }
|   '*' error {}                    |        '*' expr        %prec '&'       {$$ = e_deref(M($2)); }
|   '-' error {}                    |        '-' expr        %prec '&'       {$$ = e_neg(M($2)); }
|   '!' error {}                    |        '!' expr        %prec '&'       {$$ = e_eq(M($2), 0l); }
|   expr '?' error {$$=M($1);}      |        expr '?' expr ':' expr          {auto i = ctx.temp();
                                             $$ = e_comma(e_cor(e_cand(M($1), e_comma(C(i) %= M($3), 1l)), C(i) %= M($5)), C(i)); }
%%

yy::conj_parser::symbol_type yy::yylex(lexcontext& ctx)
{
    const char* anchor = ctx.cursor;
    ctx.loc.step();
    auto s = [&](auto func, auto&&... params) {ctx.loc.columns(ctx.cursor - anchor); return func(params..., ctx.loc); };
%{
    re2c:yyfill:enable = 0;
    re2c:define:YYCTYPE = "char";
    re2c:define:YYCURSOR = "ctx.cursor";
    "return"            { return s(conj_parser::make_RETURN); }
    "while" | "for"     { return s(conj_parser::make_WHILE); }
    "var"               { return s(conj_parser::make_VAR); }
    "if"                { return s(conj_parser::make_IF); }

    [a-zA-Z_] [a-zA-Z_0-9]* { return s(conj_parser::make_IDENTIFIER, std::string(anchor, ctx.cursor)); }

    "\"" [^\"]* "\""        {return s(conj_parser::make_STRINGCONST, std::string(anchor+1, ctx.cursor-1)); }
    [0-9]+                  {return s(conj_parser::make_NUMCONST, std::stol(std::string(anchor,ctx.cursor))); }

    "\000"              { return s(conj_parser::make_END); }
    "\r\n" | [\r\n]     { ctx.loc.lines();              return yylex(ctx); }
    "//" [^\r\n]*       { return yylex(ctx);                                }
    [ \t\v\b\f]          { ctx.loc.columns();            return yylex(ctx); }

    "&&"                { return s(conj_parser::make_AND); }
    "||"                { return s(conj_parser::make_OR); }
    "--"                { return s(conj_parser::make_MM); }
    "!="                { return s(conj_parser::make_NE); }
    "++"                { return s(conj_parser::make_PP); }
    "=="                { return s(conj_parser::make_EQ); }
    "+="                { return s(conj_parser::make_PL_EQ); }
    "-="                { return s(conj_parser::make_MI_EQ); }
    .                   { return s([](auto...s){return conj_parser::symbol_type(s...);}, (conj_parser::token_type(ctx.cursor[-1]&0xFF))); }

    %}  
}

void yy::conj_parser::error(const yy::location& l, const std::string& m)
{
    std::cerr << (l.begin.filename ? l.begin.filename->c_str() : "(undefined)");
    std::cerr << ';' << l.begin.line << ':' << l.begin.column << '-' << l.end.column << ": " << m << '\n'; 
}
#include <fstream>
#include <memory>
#include <unordered_map>
#include <functional>
#include <numeric>
#include <set>

/* GLOBAL DATA */
std::vector<function> func_list;
static bool pure_fcall(const expression& exp)
{
    /* identify the called function. note that the function could be any expression, not only a function identifier. */
    if(const auto& p = exp.params.front(); is_ident(p) && is_function(p.ident))
        if(auto called_function = p.ident.index; called_function < func_list.size())
            if(const auto & f = func_list[called_function]; f.pure_known && f.pure)
             return true;
    return false;
}

bool expression::is_pure() const
{
    for(const auto& e: params) if(!e.is_pure()) return false;
    switch(type)
    {
        case ex_type::fcall:    return pure_fcall(*this);
        case ex_type::copy:     return false;
        case ex_type::ret:      return false;
        case ex_type::loop:     return false;
        default:                return true;
    }
}

bool expression::is_compiletime_expr() const
{
    for(const auto& e: params) if(!e.is_compiletime_expr()) return false;
    switch(type)
    {
        case ex_type::number:   case ex_type::string:
        case ex_type::add:      case ex_type::neg:      case ex_type::cand:     case ex_type::cor:
        case ex_type::comma:    case ex_type::nop:
            return true;
        case ex_type::ident:
            return is_function(ident);
        default:
            return false;
    }
}

template<typename F, typename B, typename... A>
static decltype(auto) callv(F&& func, B&& def, A&&... args){
    if constexpr(std::is_invocable_r_v<B,F,A...>) { return std::forward<F>(func)(std::forward<A>(args)...); }
    else                                          { static_assert(std::is_void_v<std::invoke_result_t<F,A...>>);
                                                    std::forward<F>(func)(std::forward<A>(args)...); return std::forward<B>(def); }
}

template<typename E, typename... F>
static bool for_all_expr(E& p, bool inclusive, F&&... funcs)
{
    static_assert(std::conjunction_v<std::is_invocable<F,expression&>...>);
    return std::any_of(p.params.begin(), p.params.end(), [&](E& e) { return for_all_expr(e, true, funcs...); })
            || (inclusive && ... && callv(funcs,false,p));
}

static void FindPureFunctions()
{
    for(auto& f: func_list) f.pure_known = f.pure = false;
    do {} while(std::count_if(func_list.begin(), func_list.end(), [&](function& f)
    {
        if(f.pure_known) return false;
        std::cerr << "Identifying " << f.name << '\n';

        bool unknown_functions      = false;
        bool side_effects           = for_all_expr(f.code, true, [&](const expression& exp)
        {
            if(is_copy(exp)) { return for_all_expr(exp.params.back(), true, is_deref); }
            if(is_fcall(exp))
            {
                const auto& e = exp.params.front();
                if(!e.is_compiletime_expr()) return true;
                const auto& u = func_list[e.ident.index];
                if(u.pure_known && !u.pure) return true;
                if(!u.pure_known && e.ident.index != std::size_t(&f - &func_list[0]))
                {
                    std::cerr << "Function " << f.name << " calls unknown function " << u.name << ".\n";
                    unknown_functions = true; 
                }
            }
            return false;
        });
        if(side_effects || !unknown_functions)
        {
            f.pure_known    = true;
            f.pure          = !side_effects;
            //std::cerr << "Function " << f.name << (f.pure ? " is pure.\n" : " may have side-effects.\n");
            return true;
        }
        return false;
    }));
    for(auto& f : func_list){
        if(!f.pure_known)
        std::cerr << "Could not figure out whether " << f.name << " is a pure function or not.\n";
    }
}

std::string stringify(const expression& e, bool stmt);
std::string stringify_op(const expression& e, const char* sep, const char* delimit, bool stmt = false, unsigned first = 0, unsigned limit = ~0u)
{
    std::string result(1, delimit[0]);
    const char* fsep = "";
    for(const auto& p: e.params) { if (first){ --first; continue;} 
                                    if(!limit--) break;
                                    result += fsep; fsep = sep; result += stringify(p, stmt); }
    if(stmt) result += sep;
    result += delimit[1];
    return result;
}
std::string stringify(const expression& e, bool stmt = false){
    auto expect1 = [&]{ return e.params.empty() ? "?" : e.params.size()==1 ? stringify(e.params.front()) : stringify_op(e, "??", "()"); };
    switch(e.type)
    {
        case ex_type::nop       : return "";
        case ex_type::string    : return "\"" + e.strvalue + "\"";
        case ex_type::number    : return std:: to_string(e.numvalue);
        case ex_type::ident     : return "?FPUS"[(int)e.ident.type] + std::to_string(e.ident.index) + "\"" + e.ident.name + "\"";

        case ex_type::add       : return stringify_op(e, " + ", "()");   
        case ex_type::eq        : return stringify_op(e, " == ", "()");   
        case ex_type::cand      : return stringify_op(e, " && ", "()");   
        case ex_type::cor       : return stringify_op(e, " || ", "()");
        case ex_type::comma     : return stmt ? stringify_op(e, "; ", "{}", true) : stringify_op(e, ", ", "()");   

        case ex_type::neg       : return "-(" + expect1() + ")";
        case ex_type::deref     : return "*(" + expect1() + ")";
        case ex_type::addrof    : return "&(" + expect1() + ")";

        case ex_type::copy      : return "(" + stringify(e.params.back()) + " = " + stringify(e.params.front()) + ")";
        case ex_type::fcall     : return "(" + (e.params.empty() ? "?" : stringify(e.params.front())) + ")" + stringify_op(e,", ", "()", false, 1);
        case ex_type::loop      : return "while " + stringify(e.params.front()) + " " + stringify_op(e, "; ", "{}", true, 1);
        case ex_type::ret       : return "return " + expect1();
    }

    throw std::runtime_error("stringify: Unknown expression type!");
}

static std::string stringify(const function& f)
{
    return stringify(f.code, true); 
}

static std::string stringify_tree_node(const expression& e, int indent)
{
    std::string result(indent, ' ');
    std::string k;
    switch(e.type)
    {
        #define o(n) case ex_type::n: k.assign(#n, sizeof(#n)-1); break;
        ENUM_EXPRESSIONS(o)
        #undef o
    }

    result += k;

    if(e.params.empty()){
        result += " (" + stringify(e) + ")\n";
    } else {
        result += "\n";
        for(const auto& p : e.params){
            result += stringify_tree_node(p, indent+4);
        }
    }
    return result;
}

static std::string stringify_tree(const function& f)
{
    std::string result = "function " + f.name + ":\n";
    result += stringify_tree_node(f.code, 4);
    result += "Code Starting: " + stringify(f) + "\n\n";
    return result;
}

static bool equal(const expression& a, const expression& b)
{
    return  (a.type == b.type)
        &&  (!is_ident(a)   || (a.ident.type == b.ident.type && a.ident.index == b.ident.index))
        &&  (!is_string(a)  || a.strvalue == b.strvalue)
        &&  (!is_number(a)  || a.numvalue == b.numvalue)
        &&  std::equal(a.params.begin(), a.params.end(), b.params.begin(), b.params.end(), equal);
    
}

static void ConstantFolding(expression& e, function& f)
{
    if((is_add(e) || is_comma(e) || is_cor(e) || is_cand(e)))
    {
        //adopt all params of that same type
        for(auto j = e.params.end(); j != e.params.begin(); )
        if((--j)-> type == e.type)
        {
            // adopt all params of that parameter. Delete *j. funcall(a, b, anotherfuncall(c,d)) ----> funcall(a, b, c, d)
            auto tmp(M(j->params));
            e.params.splice(j = e.params.erase(j), std::move(tmp));
        }
    }

    /*  
        if an assign operator (copy) is used as a parameter to any other kind of expression rather than a comma or an addrof 
        create a comma sequence, such that x + 3 + (y=4) ----> x + 3 + (y=4, 4).
        if the RHS of the assign has side effects like a funcall(), use a temporary expression.
        x + (y = funcall()) ----> x + (temp=funcall(), y = temp, temp) 
    */
    if(!is_comma(e) && !is_addrof(e) && !e.params.empty())
        for(auto i = e.params.begin(), j = (is_loop(e) ? std::next(i) : e.params.end()); i != j; ++i)
            if(is_copy(*i))
            {
                auto assign = M(*i); *i = e_comma();
                if(assign.params.front().is_compiletime_expr())
                {
                    i->params.push_back(C(assign.params.front()));
                    i->params.push_front(M(assign));
                }else{
                    expression temp = f.maketemp();
                    i->params.push_back(C(temp)                        %= M(assign.params.front()));
                    i->params.push_back(M(assign.params.back())        %= C(temp));
                    i->params.push_back(M(temp));
                }
            }

    /*  
        If expr has multiple params, such as in function calls, and any of those parameters are comma expressions,
        keep only the last value in each comma expression. 
        Convert funcall((a,b,c), (d,e,f), (g,h,i)) ----> funcall(a,b,temp=c,d,e,temp2=f,g,h, func(temp, temp2, i))
        In this way, expr itself becomes a comma expression, providing the same optimization oppurtunity to the parent expression. 
    */

    if(std::find_if(e.params.begin(), e.params.end(), is_comma) != e.params.end())
    {
        auto end = (is_cand(e) || is_cor(e) || is_loop(e)) ? std::next(e.params.begin()) : e.params.end();
        for(; end != e.params.begin(); --end)
        {
            auto prev = std::prev(end);
            if(is_comma(*prev) && prev->params.size() > 1) break;
        }
        expr_vec comma_params;
        for(expr_vec::iterator i = e.params.begin(); i != end; ++i)
        {
            if(std::next(i) == end)
            {
                if(is_comma(*i) && i->params.size() > 1)
                    comma_params.splice(comma_params.end(), i->params, i->params.begin(), std::prev(i->params.end()));
            }
            else if (!i->is_compiletime_expr())
            {
                expression temp = f.maketemp();
                if(is_comma(*i) && i->params.size() > 1)
                    comma_params.splice(comma_params.end(), i->params, i->params.begin(), std::prev(i->params.end()));
                comma_params.insert(comma_params.end(), C(temp) %= M(*i));
                *i = M(temp);
            }
        }
        if(!comma_params.empty())
        {
            /* 
                if the condition to a loop statement is a comma expression,
                replicate the expression to make it better optimizable
                while(a,b,c) { code } ----> a; b; while(c) {code; a; b; }
            */
            if(is_loop(e)) { for(auto &f : comma_params) e.params.push_back(C(f)); }
            comma_params.push_back(M(e));
            e = e_comma(M(comma_params));
        }
    }

    switch(e.type)
    {   
        case ex_type::add:
        {
            // Count the sum of literals
            long tmp = std::accumulate(e.params.begin(), e.params.end(), 0l,
                                        [](long n, auto& p ) { return is_number(p) ? n + p.numvalue : n;});
            // And remove them
            e.params.remove_if(is_number);
            // Adopt all negated adds: x + -(y + z) ----> x + -(y) + -(z)
            for(auto j = e.params.begin(); j != e.params.end(); ++j)
                if(is_neg(*j) && is_add(j->params.front()))
                {
                    auto tmp(std::move(j->params.front().params));
                    for(auto& p: tmp) p = e_neg(M(p));
                    e.params.splice(j = e.params.erase(j), std::move(tmp));
                }
            if(tmp != 0) e.params.push_back(tmp);
            if(std::count_if(e.params.begin(), e.params.end(), is_neg) > long(e.params.size()/2))
            {
                for(auto& p: e.params) p = e_neg(M(p));
                e = e_neg(M(e));
            }
            break;
        }
        case ex_type::neg:
            //if the parameter is a literal, replace it with a negated version of it.
            if(is_number(e.params.front())) e = -e.params.front().numvalue;
            else if(is_neg(e.params.front())) e = C(M(e.params.front().params.front()));
            break;

        case ex_type::eq:
            if(is_number(e.params.front()) && is_number(e.params.back()))
             e = long(e.params.front().numvalue == e.params.back().numvalue);
             else if(equal(e.params.front(), e.params.back()) && e.params.front().is_pure())
             e = 1l;
             break;

        case ex_type::deref:
            if(is_addrof(e.params.front())) e = C(M(e.params.front().params.front()));
            break;

        case ex_type::addrof:
            if(is_deref(e.params.front())) e = C(M(e.params.front().params.front()));
            break;

        case ex_type::cand:
        case ex_type::cor:
        {
            auto value_kind = is_cand(e) ? [](long v){ return v!=0; } : [] (long v){ return v==0; };
            e.params.erase(std::remove_if(e.params.begin(), e.params.end(),
                                          [&](expression& p) { return is_number(p) && value_kind(p.numvalue); }),
                                          e.params.end());
            if(auto i = std::find_if(e.params.begin(),e.params.end(),[&](const expression& p)
                                    { return is_number(p) && !value_kind(p.numvalue); });
                                    i != e.params.end())
            {
                while(i!=e.params.begin() && std::prev(i)->is_pure()) { --i; }
                e.params.erase(i, e.params.end());
                e = e_comma (M(e), is_cand(e) ? 0l : 1l);
            }
            break;
        }

        case ex_type::copy:
        {
            auto& tgt = e.params.back(), &src = e.params.front();
            /* 
                If an assign-statement assigns into itself, and the expression has no side effects, replace with the lhs.
            */
            if(equal(tgt, src) && tgt.is_pure())
                e = C(M(tgt));
            else
            {
                expr_vec comma_params;
                for_all_expr(src, true, [&](auto& e) { if(equal(e, tgt)) comma_params.push_back(C(e = f.maketemp()) %= C(tgt)); });
                if(!comma_params.empty())
                {
                    comma_params.push_back(M(e));
                    e = e_comma(M(comma_params));
                }
            }
            break;
        }
        case ex_type::loop:
        /* if the loop condition is a literal zero (false), delete the code that is never executed. */
            if(is_number(e.params.front()) &&  !e.params.front().numvalue) { e = e_nop(); break; }
            [[fallthrough]];
        case ex_type::comma:
        for(auto i = e.params.begin(); i != e.params.end(); )
        {
            /* For while(), leave the condition expression untouched.
               For comma, leave the "final" expression untouched. */
            if(is_loop(e))
                {if(i==e.params.begin()) { ++i; continue; }}
            else
                {if(std::next(i) == e.params.end()) break;}
            /* Delete all pure params except the last one. */
            if(std::next(i) == e.params.end()) break;

            if(i->is_pure())
                { i = e.params.erase(i); }
            else switch (i->type)
            {
                default:
                    ++i;
                    break;
                case ex_type::fcall:
                /* Even if the function call is not pure, it might be because of parameters, not the function itself.
                    Check if only need to keep the parameters. */
                    if(!pure_fcall(e)) {++i; break;}
                    [[fallthrough]];
                case ex_type::add:
                case ex_type::neg:
                case ex_type::eq:
                case ex_type::addrof:
                case ex_type::deref:
                case ex_type::comma:
                /* Adobt all params of the param. Delete *i. */
                    auto tmp(std::move(i->params));
                    e.params.splice(i = e.params.erase(i), std::move(tmp));
            }
        }
        /* delete all parameters following a return statement or an infinite loop */
            if(auto r = std::find_if(e.params.begin(), e.params.end(), [](const expression& e) { return is_ret(e) || (is_loop(e) && is_number(e.params.front()) && e.params.front().numvalue != 0); });
               r != e.params.end() && ++r != e.params.end())
               {
                //std::cerr << std::distance(r,e.params.end()) << " dead expressions deleted\n";
                e.params.erase(r, e.params.end());
               }
            
            if(e.params.size() == 2)
            {
                /* if the last element in the list is the same as the preceding assign-target, delete the last element. x = (a=3, a) -> x = (a=3) */
                auto& last = e.params.back(), &prev = *std::next(e.params.rbegin());
                if(is_copy(prev) && equal(prev.params.back(), last))
                    e.params.pop_back();
            }
            if(e.params.size() == 1 && !is_loop(e))
            {
                e = C(M(e.params.front()));
            }
            break;

        default:
            break;
    }
    switch(e.params.size())
    {
        case 1: if(is_add(e))                           e= C(M(e.params.front()));
                else if (is_cor(e) || is_cand(e))       e = e_eq(e_eq(M(e.params.front()), 0l), 0l);
                break; 
        case 0: if(is_add(e) || is_cor(e))              e = 0l;
                else if(is_cand(e))                     e = 1l;
    }
}

static void DoConstantFolding()
{
    do {} while (std::any_of(func_list.begin(), func_list.end(), [&](function& f){
        /* 
            Recalculate function purity; the status may have changed 
            as unreachable statements have been deleted or altered.
        */
        FindPureFunctions();
        std::string text_before = stringify(f);
        //std::cerr << "Before: " << text_before << '\n';
        //std::cerr << stringify_tree(f);
        for_all_expr(f.code, true, [&](expression& e){ ConstantFolding(e,f); });
        return stringify(f) != text_before;
    }));
}

#include "transform_iterator.hh"
#include "shuffle.hh"
#include <string_view>
#include <optional>
#include <variant>

#define ENUM_STATEMENTS(o)      /* flags: #write_params, has_side_effects, special constructor; name */\
        o(0b000, nop)           /* placeholder that does nothing.                                                */  \
        o(0b101,init)           /* p0 <--- &IDENT + value (assign a pointer to name resource with offset)        */  \
        o(0b100,add)            /* p0 <--- p1 + p2                                                               */  \
        o(0b100,neg)            /* p0 <--- -p1                                                                   */  \
        o(0b100,copy)           /* p0 <--- p1   (assign a copy of another variable)                              */  \
        o(0b100,read)           /* p0 <--- *p1  (reading dereference)                                            */  \
        o(0b010,write)          /* *p0 <--- p1  (writing dereference)                                            */  \
        o(0b100,eq)             /* p0 <--- p1 == p2                                                              */  \
        o(0b011,ifnz)           /* if(p0 != 0) <--- JMP branch                                                   */  \
        o(0b110,fcall)          /* p0 <--- CALL(p1, <LIST>)                                                      */  \
        o(0b010,ret)            /* RETURN p0;                                                                    */  \

#define o(_,n) n,
#define p(f,n) f,
#define q(f,n) #n,
enum class st_type{ ENUM_STATEMENTS(o) };
static constexpr unsigned char st_flags[] { ENUM_STATEMENTS(p) };
static constexpr const char* const st_names[] { ENUM_STATEMENTS(q) };
#undef q
#undef p
#undef o

template<typename T, typename... Bad>
using forbid1_t = std::enable_if_t<(... && !std::is_same_v<Bad, std::decay_t<T>>)>;
template <typename...U>
struct forbid_t { template <typename...T> using in = std::void_t<forbid1_t<T,U...>...>; };

template <typename Iterator, typename PointedType, typename Category>
using require_iterator_t = std::enable_if_t
<   std::is_convertible_v<typename std::iterator_traits<Iterator>::value_type,      PointedType>
 && std::is_convertible_v<typename std::iterator_traits<Iterator>::iterator_category,Category>>;

struct statement
{
    typedef unsigned reg_type;
    static constexpr reg_type nowhere = ~reg_type();

    st_type                 type{ st_type::nop };
    std::string             ident{};            //For init: reference to globals, empty=none
    long                    value{};            //For init: literal/offset
    std::vector<reg_type>   params{};           //Variable indexes
    statement*              next{nullptr};      //Pointer to next stmt in the chain. nullptr = last.
    statement*              cond{nullptr};      //For ifnz; if var[p0] <> 0, cond overrides next.

    // Construct with type and zero or more register params
    statement() {}
    template<class...T, class=forbid_t<st_type,long,statement*>::in<T...>>
    statement(st_type t, T&&...r)           : statement(std::forward<T>(r)...) { type=t; }

    template<class...T>
    statement(reg_type tgt, T&&...r)        : statement(&tgt, &tgt+1, std::forward<T>(r)...) {}

    // Special Types that also force the statement type:
    template<class...T, class=forbid_t<st_type,long>::in<T...>>
    statement(std::string_view i, long v, T&&...r)  : statement(st_type::init, std::forward<T>(r)...) { ident=i; value=v; }
    
    template<class...T, class=forbid_t<st_type,statement*>::in<T...>>
    statement(statement* b, T&&...r)                : statement(st_type::ifnz, std::forward<T>(r)...) { cond=b; }

    // An iterator range can be used to assign register params
    template<class...T, class It, class=require_iterator_t<It, reg_type, std::input_iterator_tag>>
    statement(It begin, It end, T&&...r)            : statement(std::forward<T>(r)...) { params.insert(params.begin(), begin, end); }

    template<class...T>
    void Reinit(T&&... r) // Reinitialize statement as a different one, without changing -> next
    {
        auto n = next;
        *this = statement(std::forward<T>(r)...);
        next = n;
    }

    template<typename F>
    auto ForAllRegs(F&& func, std::size_t begin=0, std::size_t end = ~size_t())
    {
        return std::any_of(params.begin()+begin, params.begin()+std::min(end, params.size()),
                          [&](reg_type& p) { return p != nowhere && callv(func,false,p, &p-&params[0]); });
    }

    template<typename F>
    auto ForAllWriteRegs(F&& func) { return ForAllWriteRegs(std::forward<F>(func), 0, NumWriteRegs()); }
    template<typename F>
    auto ForAllReadRegs(F&& func) { return ForAllWriteRegs(std::forward<F>(func), 0, NumWriteRegs(), params.size()); }
    
    reg_type& lhs() { return params.front(); }
    reg_type& rhs() { return params.back(); }

    std::size_t NumWriteRegs() const { return st_flags[unsigned(type)]/4;}
    bool HasSideEffects() const { return st_flags[unsigned(type)]&2;}

    void Dump(std::ostream& out) const
    {
        out << '\t' << st_names[unsigned(type)] << '\t';
        for(auto u: params) out << " R" << u;
        if(type == st_type::init) { out << " \"" << ident << "\" " << value; } 
    }
};

struct compilation
{
    std::vector<std::unique_ptr<statement>> all_statements; // All Statements

    template<typename... T>
    statement* CreateStatement(T&&... args) { return CreateStatement(new statement(std::forward<T>(args)...)); }
    statement* CreateStatement(statement*s) { return all_statements.emplace_back(s).get(); }

    #define o(f,n) /* f: flag that indicates if there's a special constructor inside that does not need the type */ \
    template<typename... T> \
    inline statement* s_##n(T&&... args) { if constexpr(f)  return CreateStatement(std::forward<T>(args)...); \
                                           else return CreateStatement(st_type::n, std::forward<T>(args)...); }
    ENUM_STATEMENTS(o)
    #undef o

    std::map<std::string, std::size_t>  function_parameters; // Number of parameters in each function
    std::map<std::string, statement*>   entry_points;

    std::string string_constants;

    void BuildStrings()
    {
        std::vector<std::string> strings;
        for(auto& f: func_list)
            for_all_expr(f.code, true, is_string, [&](const expression& exp)
            {
                strings.push_back(exp.strvalue + '\0');
            });
        //Sort by length, longest first
        std::sort(strings.begin(), strings.end(), [](const std::string& a, const std::string& b)
        {
            return a.size()==b.size() ? (a < b) : (a.size() > b.size());
        });
        for(const auto& s: strings)
            if(string_constants.find(s) == string_constants.npos)
                string_constants += s;
    }

    void Dump(std::ostream& out)
    {
        struct data
        {
            std::vector<std::string> labels{};
            std::size_t done{}, referred{}; // bool would be fine if permitted by C++17
        };

        std::map<statement*, data> statistics;
        std::list<statement*> remaining_statements;

        auto add_label = [l=0lu](data& d) mutable { d.labels.push_back('L' + std::to_string(l++)); };
        
        for(const auto& [name,st]: entry_points)
        {
            remaining_statements.push_back(st);
            statistics[st].labels.push_back(name);
        }
        for(const auto& s: all_statements)
        {
            if(s->next) { auto& t = statistics[s->next]; if(t.labels.empty() && t.referred++) add_label(t); }
            if(s->cond) { auto& t = statistics[s->cond]; if(t.labels.empty()) add_label(t); }
        }
        while(!remaining_statements.empty())
        {
            statement* chain = remaining_statements.front(); remaining_statements.pop_front();
            for(bool needs_jmp = false; chain != nullptr; chain = chain -> next, needs_jmp = true)
            {
                auto& stats = statistics[chain];
                if(stats.done++)
                {
                    if(needs_jmp) { out << "\tJMP" << stats.labels.front() << '\n'; }
                    break;
                }

                for(const auto& l: stats.labels) out << l << ":\n";
                chain->Dump(out);
                if(chain->cond)
                {
                    auto& branch_stats = statistics[chain->cond];
                    out << ", JMP " << branch_stats.labels.front();
                    if(!branch_stats.done) {remaining_statements.push_front(chain->cond); }
                }
                out << '\n';
            }
        }
    }

    struct compilation_context
    {
        statement::reg_type counter;                    // Counter for next unused register number
        statement**         tgt;                        // Pointer to where the next instruction will be stored
        std::map<std::size_t, statement::reg_type> map; // AST variables to register numbers mapping 
    };
    statement::reg_type Compile(const expression& code, compilation_context& ctx)
    {
        statement::reg_type result = ~statement::reg_type();

        //make(): Create a new register (variable for the IR)
        auto make =     [&]()               { return ctx.counter++; };
        //put(): Place a given change of code at *tgt, then re-point tgt into the end of the chain.
        auto put =      [&](statement* s)   { for(*ctx.tgt = s; s; s = *ctx.tgt) ctx.tgt = &s->next; };

        switch(code.type)
        {
            case ex_type::string:
            {
                // Create an INIT statement (+ possibly integer offset) that refers to the string table
                put(s_init(result = make(), "$STR", (long) string_constants.find(code.strvalue +'\0')));
                break;
            }
            case ex_type::ident:
            {
                switch(auto& id = code.ident; id.type)
                {
                    case id_type::function: put(s_init(result = make(), id.name, 0l)); break;
                    case id_type::variable: result = ctx.map.emplace(id.index, make()).first->second; break;
                    case id_type::parameter: result = id.index; break;
                    case id_type::undefined: std::cerr << "UNDEFINED IDENTIFIER, DON'T KNOW WHAT TO DO\n"; break; 
                }
                break;
            }
            case ex_type::deref:    put(s_read(result = make(), Compile(code.params.front(), ctx))); break;
            case ex_type::neg:      put(s_neg(result =  make(), Compile(code.params.front(), ctx))); break;
            case ex_type::ret:      put(s_ret(result =          Compile(code.params.front(), ctx))); break;
            case ex_type::number:   put(s_init(result = make(), "", code.numvalue)); break;
            case ex_type::nop:      put(s_init(result = make(), "", 0L)); break;    // dummy expr
            case ex_type::addrof:   std::cerr << "NO IDEA WHAT TO DO WITH " << stringify(code) << '\n'; break; //Unhandlable

            case ex_type::add:
            case ex_type::eq:
            case ex_type::comma:
            {
                // Trivially reduce parameters from left to right
                for(auto i = code.params.begin(); i != code.params.end(); ++i)
                    if(statement::reg_type prev = result, last = result = Compile(*i, ctx); prev != statement::nowhere)
                        {   if(is_add(code)) { put(s_add(result = make(), prev, last)); }
                            else if (is_eq(code)) { put(s_eq(result = make(), prev, last));} 
                            else /* *comma, no reducer: discard everything except the last stmt */ { result = last; }}
                break;
            }
            case ex_type::copy:
                // Compile the source expression first, and then the target expression.
                // If the target expression is a pointer deref, create a WRITE statement rather than COPY.
            {    
                if(const auto& src = code.params.front(), &dest = code.params.back(); is_deref(dest))
                    { result = Compile(src, ctx); put (s_write(Compile(dest.params.front(), ctx), result)); }
                else
                    { auto temp = Compile(src, ctx); put(s_copy(result = Compile(dest, ctx), result)); }
                break; 
            }
            case ex_type::fcall:
            {
                // Compile each parameter expression, and create a subroutine call statement with those params.
                put(s_fcall(result = make(), make_transform_iterator(code.params.begin(), code.params.end(),
                                                                    [&](const expression&p){ return Compile(p,ctx); }),
                                                                    transform_iterator<statement::reg_type>{}));
                break;
            }
            case ex_type::loop:
            case ex_type::cand:
            case ex_type::cor:
            {
                // Conditional code (including while-loop)
                const bool is_and   = !is_cor(code); //while(), if(), and &&
                result              = make();
                // Three mandatory (then - else - end) statements will be created:
                statement* b_then   = s_init(result, "", is_and ? 1l : 0l);         //Then - branch
                statement* b_else   = s_init(result, "", is_and ? 0l : 1l);         //Else - branch
                statement* end      = s_nop(); b_then->next = b_else ->next = end;  //A common target for both.
                // Save a pointer to the first expression (needed for loops).
                // Take a reference to the pointer and not copy of the pointer, because the pointer will change in the loop.
                statement*& begin = *ctx.tgt;
                for(auto i = code.params.begin(); i!=code.params.end(); ++i)
                {
                    // Compile
                    statement::reg_type var = Compile(*i, ctx);
                    // Don't create a branch after contingent statements in a loop.
                    if(is_loop(code) && i!=code.params.begin()) { continue; }
                    // Immediately after the expression, create a branch on its result.
                    statement* condition = * ctx.tgt = s_ifnz(var, nullptr);
                    // With &&, the code continues in the true branch. With ::, in false branch.
                    // The other branch is tied into b_else.
                    if(is_and)  { ctx.tgt = &condition->cond; condition->next = b_else; }
                    else        { ctx.tgt = &condition->next; condition->cond = b_else; }
                }
                // The end of the statement chain is linked into b_then.
                // For loops, the chain is linked back into the start of the loop instead.
                *ctx.tgt = is_loop(code) ? begin : b_then;
                ctx.tgt = &end->next; // Code continues after the end statement.
                break;
            }
        }
        return result;
    }

    void CompileFunction(function& f)
    {
        function_parameters[f.name] = f.num_params;

        compilation_context ctx { f.num_params, &entry_points[f.name], {} };
        Compile(f.code, ctx); 
    }

    void Compile()
    {
        BuildStrings();
        for(auto& f : func_list) CompileFunction(f);
    }
};

#define o(_,n) \
inline bool is_##n(const statement& s) {return s.type == st_type::n; }
ENUM_STATEMENTS(o)
#undef o



int main(int /*argc*/, char** argv)
{
    std::string filename = argv[1];
    std::ifstream f(filename);
    std::string buffer(std::istreambuf_iterator<char>(f), {});

    lexcontext ctx;
    ctx.cursor = buffer.c_str();
    ctx.loc.begin.filename = &filename;
    ctx.loc.end.filename = &filename;

    yy::conj_parser parser(ctx);
    parser.parse();
    func_list = std::move(ctx.func_list);

    std::cerr << "Initial\n";
    for(const auto& f : func_list) std::cerr << stringify_tree(f);

    DoConstantFolding();

    std::cerr << "Final\n";
    for(const auto& f: func_list) std::cerr << stringify_tree(f);

    compilation code;
    code.Compile();

    std::cerr << "Compiled Code\n";
    code.Dump(std::cerr);

    code.Optimized();

    std::cerr << "Optimized Code\n";
    code.Dump(std::cerr);
}