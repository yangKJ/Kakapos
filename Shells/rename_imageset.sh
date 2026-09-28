#!/bin/bash

echo "查询验证本目录下所有imageset 目录, \n不一致的会列出, 并可控制修改"

# /// 1 自动 2手动
CheckType=1
# $0当前Shell程序的文件名
# 当前shell所在目录
CheckDir=`dirname $0`
AllSourceAssets=() # all imageset
AllUnEqualAssets=() # all uneqal item

# 在linux中内置分隔符IFS(Internal Field Seperator)默认为空格、制表符、换行符
# 手动设置IFS排除空格分隔符
IFS=$'\n'


# // MARK: -  public
function _throwError() {
    eval "$1" || { alert "exec failed: ""$1"; exit -1; }
}


prepare_data() {
    echo ">>prepare_data"
    echo -n "1当前目录(默认) 2手动输入目录, 请选择: ";
    read mCheck
    if [[ $mCheck == 2 ]]; then
        CheckType=2
        echo -n "请输入目录: "
        read mDir
        CheckDir=$mDir
    fi

}


# // MARK: -  read dir

function read_dir(){
    for file in `ls $1`
    do
        FPath=$1"/"$file
         if [ -d $FPath ]; then
             # // 当前是目录
             PathSuffix="${FPath##*.}"
             if [[ $PathSuffix == "imageset" ]]; then
                 AllSourceAssets+=($FPath)
             else
                 read_dir $1"/"$file
             fi
         else
             # 文件
             continue
         fi
    done
}

list_all_assets() {
    echo ">>list_all_assets"
    echo ">>最后遍历目录>" $1
    dir=$1
    if test -n  $dir ; then
        echo ">>目录有效"
    else
        _throwError "目录必须有"
    fi
    read_dir $dir
    echo "总图片个数>"  ${#AllSourceAssets[@]}
    sleep 1
}

check_item_path() {
    DirName=`basename $1 .imageset`
    # /path/app3.imageset
    for file in `ls $1`; do
        FPath=$1"/"$file
        PathSuffix="${FPath##*.}"
        if [[ $PathSuffix == "json" ]]; then
            continue
        else
            FileName=`basename $file .$PathSuffix`
            FileName=${FileName%%@3x}
            FileName=${FileName%%@2x}
            # echo $FileName $DirName
            if [[ $FileName == $DirName ]]; then
                continue
            else
                AllUnEqualAssets+=($1)
                break
            fi

        fi
    done
}

modify_item_path() {
    DirName=`basename $1 .imageset`
    OriginPicName=""
    TOPicName=$DirName
    # /path/app3.imageset

    # /// 先处理picture
    for file in `ls $1`; do
        FPath=$1"/"$file
        PathSuffix="${FPath##*.}"
        if [[ $PathSuffix == "json" ]]; then
            continue
        else
            FileName=`basename $file .$PathSuffix`
            FileName=${FileName%%@3x}
            FileName=${FileName%%@2x}
            OriginPicName=$FileName
            # 修改pic  # 修改json
            old=$OriginPicName".$PathSuffix"
            new=$TOPicName".$PathSuffix"
            mv $1"/"$old  $1"/"$new
            (cat "$1/Contents.json" ; echo) | sed "s/$old/$new/" | perl -pe "chomp if eof" > "$1/Contents.json.1"
            mv "$1/Contents.json.1" "$1/Contents.json"
            sleep 0.1


            old=$OriginPicName"@3x.$PathSuffix"
            new=$TOPicName"@3x.$PathSuffix"
            mv $1"/"$old  $1"/"$new
            (cat "$1/Contents.json" ; echo) | sed "s/$old/$new/" | perl -pe "chomp if eof" > "$1/Contents.json.1"
            mv "$1/Contents.json.1" "$1/Contents.json"
            sleep 0.1

            old=$OriginPicName"@2x.$PathSuffix"
            new=$TOPicName"@2x.$PathSuffix"
            mv $1"/"$old  $1"/"$new
            (cat "$1/Contents.json" ; echo) | sed "s/$old/$new/" | perl -pe "chomp if eof" > "$1/Contents.json.1"
            mv "$1/Contents.json.1" "$1/Contents.json"
            sleep 0.1

            # //iOS image 2x/3x 图片名字一致
            # break
        fi
    done

    rm -rf "$1/Contents.json.1"
}

# // MARK: -  measure

test_api() {
    prepare_data
    list_all_assets $CheckDir

    echo ">>check_item_path"
    #${#array[@]}获取数组长度
    for(( i=0;i<${#AllSourceAssets[@]};i++)) do
        ItemDir=${AllSourceAssets[i]};
        check_item_path $ItemDir
    done;

    AllSourceAssets=()
    echo "需要修改图片个数>"  ${#AllUnEqualAssets[@]}
    sleep 1
    for(( i=0;i<${#AllUnEqualAssets[@]};i++)) do
        ItemDir=${AllUnEqualAssets[i]};
        echo ">>需要修改:" $ItemDir
    done;
    sleep 0.5


    if [[ ${#AllUnEqualAssets} == 0 ]]; then
        return 0
    fi


    echo -n "是否自动更正: 0否(默认)  1自动: "
    read mModify
    if [[ $mModify == 1 ]]; then
        for(( i=0;i<${#AllUnEqualAssets[@]};i++)) do
            ItemDir=${AllUnEqualAssets[i]};
            modify_item_path $ItemDir
        done;
    fi
}

main() {
    test_api
}

main
