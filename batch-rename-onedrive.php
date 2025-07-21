<?php
function prompt($question = ''){
    echo $question . PHP_EOL;

    return rtrim(fgets(STDIN));
}

/**
 * @param $str
 * @param $showYesToAll
 * @param $varToStore
 * @return bool
 */
function confirm($str = '', $showYesToAll = false, &$varToStore = null): bool
{
    $q = $showYesToAll ? ' [Y/n/A]' : '(Y/n)';
    echo $str . $q;
    $input = rtrim(fgets(STDIN));
    if($showYesToAll && in_array(mb_strtolower($input), ['a', 'all'])){
        $varToStore = true;
        return true;
    }
    if(!in_array(mb_strtolower($input), ['n', 'no'])){
        return true;
    }
    return false;
}
function info($str = '', $replaceLastLine = false){
    echo $str . ($replaceLastLine ? "\r" : PHP_EOL);
}
$computerName = getenv('COMPUTERNAME');
$dir = getcwd();
$yesToAll = false;
$loopCount = 0;
$dirCount = 0;
$deleteFail = [];
$renameFail = [];
info(sprintf('Your computer name is: %s', $computerName));
info(sprintf('The working directory is: %s', $dir));
if(!confirm('Is it correct ?')){
    $dir = prompt('Enter directory path:');
    if(!file_exists($dir) || !is_readable($dir)){
        info(sprintf('%s does not exist or non-readable', $dir));
        exit('Goodbye.');
    }
}
$iterator = new RecursiveDirectoryIterator($dir, FilesystemIterator::SKIP_DOTS);
/** @var RecursiveIteratorIterator|\SplFileInfo[] $iterator */
$iterator = new RecursiveIteratorIterator($iterator, RecursiveIteratorIterator::SELF_FIRST);
info(sprintf('Finding files contains "%s" in name, then delete original file.', $computerName));
foreach ($iterator as $k => $item) {
    ++$loopCount;
    if ($item->isDir()) {
        if($dirCount % 100 === 0){
            info(sprintf('Scanned %d files in %d directories', $loopCount, $dirCount), true);
        }
        ++$dirCount;
        continue;
    }
    $pattern = sprintf('/-%s\.?%s$/', preg_quote($computerName,'/'), preg_quote($item->getExtension(),'/'));
    if(preg_match($pattern, $item->getBasename())){
        info();
        info(sprintf('%s MATCHED', $item->getRealPath()));
        if (!$item->isFile()){
            info(sprintf('WARNING: %s not is file', $item->getBasename()));
            var_dump($item->getType());
            continue;
        }
        $orgFile = preg_replace($pattern, '', $item->getBasename()) . ($item->getExtension() ? '.' . $item->getExtension() : '');
        $fullOrgPath = dirname($item->getRealPath()) . DIRECTORY_SEPARATOR . $orgFile;
        if(file_exists($fullOrgPath)){
            info(sprintf('INFO: File: %s exist.', $orgFile));
            if($yesToAll || confirm('Delete original file ?', true, $yesToAll)){
                $rs = unlink($fullOrgPath);
                if(!$rs){
                    $deleteFail[] = $fullOrgPath;
                    info('WARNING: remove failed');
                }
            }
        }
        if(!file_exists($fullOrgPath) && ($yesToAll || confirm('Rename duplicated to original file ?', true, $yesToAll))){
            info(sprintf('Renaming to original: %s', $orgFile));
            $rs = rename($item->getRealPath(), $fullOrgPath);
            if(!$rs){
                $renameFail[] = $item->getRealPath();
                info('WARNING: rename failed');
            }
        }elseif(confirm('Delete duplicated file ?')){
            info(sprintf('Removing duplicated: %s', $item->getBasename()));
            $rs = unlink($item->getRealPath());
            if(!$rs){
                $deleteFail[] = $item->getRealPath();
                info('WARNING: remove failed');
            }
        }
    }
}

if(count($deleteFail)){
    info(sprintf('INFO: %d failed to delete', count($deleteFail)));
    info();
    foreach ($deleteFail as $value) {
        info($value);
    }
    info();
}

if(count($renameFail)){
    info(sprintf('INFO: %d failed to rename', count($renameFail)));
    info();
    foreach ($renameFail as $value) {
        info($value);
    }
    info();
}
exit('Operation done. Quiting.');